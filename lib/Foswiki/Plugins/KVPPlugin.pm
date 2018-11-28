# See bottom of file for license and copyright information

# TODO
# 1. Create initial values based on form when attaching a form for
#    the first time.
# 2. Allow appearance of button to be given in preference.

# =========================
package Foswiki::Plugins::KVPPlugin;

use strict;
use warnings;

use Error ':try';
use Assert;

use Foswiki::Func ();
use Foswiki::Plugins::KVPPlugin::Workflow ();
use Foswiki::Plugins::KVPPlugin::ControlledTopic ();
use Foswiki::OopsException ();
use Foswiki::Sandbox ();

use Foswiki::Contrib::MailTemplatesContrib;
use Foswiki::Plugins::ModacHelpersPlugin;

use HTML::Entities;
use JSON;

use constant FORCENEW => 1;
use constant NOCACHE => 2;
use constant MAXREV => 99999;

our $VERSION = '2.0';
our $RELEASE = "2.0";
our $SHORTDESCRIPTION = 'Kontinuierliche Verbesserung im Wiki';
our $NO_PREFS_IN_TOPIC = 1;
our $pluginName       = 'KVPPlugin';
our %cache;
our $isStateChange;
# Although the origin is quick to calculate it is called often enough to be worth being cached
our $originCache;
our $markAsStub;

our $unsafe_chars = "<&>'\"";

sub initPlugin {
    my ( $topic, $web ) = @_;

    %cache = ();

    our $markAsStub = 0;

    Foswiki::Func::registerRESTHandler(
        'changeState', \&_changeState,
        authenticate => 1, http_allow => 'POST', validate => 1 );
    Foswiki::Func::registerRESTHandler(
        'fork', \&_restFork,
        authenticate => 1, http_allow => 'POST,GET', validate => 0 );
    Foswiki::Func::registerRESTHandler(
        'link', \&_restLink,
        authenticate => 0, http_allow => 'GET', validate => 0 );
    Foswiki::Func::registerRESTHandler(
        'history', \&_restHistory,
        authenticate => 1, http_allow => 'GET', validate => 0 );

    Foswiki::Func::registerTagHandler(
        'WORKFLOWSTATE', \&WORKFLOWSTATE );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWHISTORY', \&_WORKFLOWHISTORY );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWTRANSITION', \&_WORKFLOWTRANSITION );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWTRANSITIONVUE', \&_WORKFLOWTRANSITIONVUE );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWFORK', \&_WORKFLOWFORK );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWGETREVFOR', \&_WORKFLOWGETREVFOR );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWMETA', \&WORKFLOWMETA );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWSUFFIX', \&_WORKFLOWSUFFIX );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWCONTRIBUTORS', \&_WORKFLOWCONTRIBUTORS );
    Foswiki::Func::registerTagHandler(
        'GETWORKFLOWROW', \&_GETWORKFLOWROW );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWALLOWS', \&_WORKFLOWALLOWS );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWEDITPERM', \&_WORKFLOWEDITPERM );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWCANTRANSITION', \&_WORKFLOWCANTRANSITION );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWORIGIN', \&_WORKFLOWORIGIN );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWPROPONENTS', \&_WORKFLOWPROPONENTS );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWDENIEDFIELDS', \&_WORKFLOWDENIEDFIELDS );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWDISPLAYTABS', \&_WORKFLOWDISPLAYTABS );

    my $context = Foswiki::Func::getContext();
    if($context->{view} || $context->{edit} || $context->{comparing} || $context->{oops}  || $context->{manage} || $context->{KVPPluginSetContextOnInit}) {
        # init the displayed topic to set according contexts for skin
        $originCache = _getOrigin( $topic );
        $context->{'KVPContextsSet'} = 1;
        my $controlledTopic = _initTOPIC( $web, $topic );
        if ($controlledTopic) {
            $context->{'KVPControlled'} = 1;
            if ($controlledTopic->canEdit()) {
                $context->{'KVPEdit'} = 1;
            } else {
                $context->{'modacRevokeChangePermission'} = 1;
            }
            if ($controlledTopic->canMove()) {
                $context->{'KVPMove'} = 1;
            } else {
                $context->{'modacRevokeMovePermission'} = 1;
            }
            if ($controlledTopic->getRow( 'approved' )) {
                my $suffix = _WORKFLOWSUFFIX();
                $context->{'KVPShowMenue'} = 1 if $controlledTopic->getWorkflowPref('AlwaysShowMenue');
                if (Foswiki::Func::topicExists($web, "$topic$suffix")) {
                    $context->{'KVPHasDiscussion'} = 1;
                    $context->{'KVPIsApproved'} = 1;
                }
            } else {
                if($originCache eq $topic) {
                    $context->{'KVPIsDraft'} = 1;
                } else {
                    # Hmpf, KVPIsDiscussion was used for all non-approved
                    # topics, even drafts. Because it is widely used I can not
                    # simply change it's meaning here, so I have to introduce
                    # this strangely named thing.
                    $context->{'KVPIsForkedDiscussion'} = 1;
                }
                $context->{'KVPIsDiscussion'} = 1; # for backwards compatibility
                $context->{'KVPShowMenue'} = 1;
                $context->{'KVPIsNotApproved'} = 1;
            }
        }
    } else {
        undef $originCache;
    }

    # Copy/Paste/Modify from MetaCommentPlugin
    # SMELL: this is not reliable as it depends on plugin order
    # if (Foswiki::Func::getContext()->{SolrPluginEnabled}) {
    if ($Foswiki::cfg{Plugins}{SolrPlugin}{Enabled}) {
      require Foswiki::Plugins::SolrPlugin;
      Foswiki::Plugins::SolrPlugin::registerIndexAttachmentHandler(
        \&indexAttachmentHandler
      );
      Foswiki::Plugins::SolrPlugin::registerIndexTopicHandler(
        \&indexTopicHandler
      );
    }

    return 1;
}

# Adds a message to %BROADCASTMESSAGE%
sub _broadcast {
    my ( $message ) = @_;
    my $oldMessage = Foswiki::Func::getPreferencesValue( 'BROADCASTMESSAGE' ) || '';
    unless ($oldMessage =~ m/\Q$message\E/) {
        Foswiki::Func::setPreferencesValue( 'BROADCASTMESSAGE', "$oldMessage<p>$message</p>" );
    }
}

sub _WORKFLOWDENIEDFIELDS {
    my ( $session, $params, $topic, $web ) = @_;

    my $rev = $params->{rev};
    $web = $params->{web} || $web;
    $topic = $params->{topic} || $topic;
    my $nocache = ( ($params->{nocache}) ? 1 : undef );

    my $controlledTopic = _initTOPIC( $web, $topic, $rev, undef, $nocache );
    return '' unless $controlledTopic;

    return join(', ', $controlledTopic->getDeniedFields());
}

sub _WORKFLOWDISPLAYTABS {
    my($session, $params) = @_;
    return '' unless $params->{web} && $params->{workflowname};
    my $workflow = new Foswiki::Plugins::KVPPlugin::Workflow( $params->{web}, $params->{workflowname} );
    return '' unless $workflow;
    if($params->{renderTabMacro} && $params->{renderTabMacro} eq "true") {
        my $formattedString = "";
        for my $tabeName ($workflow->getDisplayTabs()) {
            my $renderTab = '%TAB{"%MAKETEXT{"%1"}%"}% %TMPL:P{"searchgrid_tabs" extraquery="workflowstate_displayedtab_s:\"%1\""}% %ENDTAB%';
            my $find = '%1';
            $renderTab =~ s/$find/$tabeName/g;
            $formattedString = $formattedString . $renderTab;
        }
        return $formattedString;
    }
    else {
        return join(", ", $workflow->getDisplayTabs());
    }
}

# Tag handler for WORKFLOWALLOWS
# Will return 1 if the user is allowed to the action in this topic
sub _WORKFLOWALLOWS {
    my ( $session, $params, $topic, $web ) = @_;

    my $rev = $params->{rev};
    my $rWeb = $params->{web} || $web;
    my $rTopic = $params->{topic} || $topic;
    my $action = $params->{_DEFAULT} || 'allowedit';
    my $nocache = ( ($params->{nocache}) ? 1 : undef );

    my $controlledTopic = _initTOPIC( $rWeb, $rTopic, $rev, undef, $nocache );

    if (defined $params->{emptyIs} || defined $params->{nonEmptyIs}) {
        my $row;
        if($controlledTopic) {
            $row = $controlledTopic->getRow($action);
        } else {
            $row = $params->{uncontrolled};
        }
        return $params->{emptyIs} if ((!defined $row || $row eq '') && defined $params->{emptyIs});
        return $params->{nonEmptyIs} if (defined $row && $row ne '' && defined $params->{nonEmptyIs});
    }

    return $params->{uncontrolled} unless $controlledTopic;
    return $controlledTopic->isAllowing($action) ? 1 : 0;
}

# Tag handler for WORKFLOWEDITPERM
# Will return 1 if the user is allowed to edit this topic
sub _WORKFLOWEDITPERM {
    my ( $session, $params, $topic, $web ) = @_;

    my $rev = $params->{rev};
    my $rWeb = $params->{web} || $web;
    my $rTopic = $params->{topic} || $topic;

    my $controlledTopic = _initTOPIC( $rWeb, $rTopic, $rev );
    if ($controlledTopic) {
        return $controlledTopic->canEdit() ? 1 : 0;
    }
    # No workflow...
    # Does Foswiki permit editing?
    return Foswiki::Func::checkAccessPermission(
        'CHANGE', $Foswiki::Plugins::SESSION->{user},
        undef, $rTopic, $rWeb, undef
    ) ? 1 : 0;
}

# Tag handler for WORKFLOWCANTRANSITION
# Will return true if action is possible.
sub _WORKFLOWCANTRANSITION {
    my ( $session, $params, $topic, $web ) = @_;

    my $rWeb = $params->{web} || $web;
    my $rTopic = $params->{topic} || $topic;
    my $action = $params->{_DEFAULT};
    my $controlledTopic = _initTOPIC( $rWeb, $rTopic );

    return '0' unless $controlledTopic;
    return ($controlledTopic->haveNextState($action))?'1':'0';
}

# Tag handler for WORKFLOWCONTRIBUTORS
# Will return a list of users that have contributed to this topic until last ACCEPT.
sub _WORKFLOWCONTRIBUTORS {
    my ( $session, $params, $topic, $web ) = @_;

    my $rev = $params->{rev};
    my $rWeb = $params->{web} || $web;
    my $rTopic = $params->{topic} || $topic;
    my $state = $params->{state};
    my $controlledTopic = _initTOPIC( $rWeb, $rTopic, $rev );

    return '' unless $controlledTopic;
    return $controlledTopic->getContributors($state);
}

# XXX Copy/Paste from Workflow::_isAllowed
# Checks if the User is in a list
sub isInList {
    my ($allow) = @_;
    if (
            ref( $Foswiki::Plugins::SESSION->{user} )
            && $Foswiki::Plugins::SESSION->{user}->can("isInList")
        )
    {
        return $Foswiki::Plugins::SESSION->{user}->isInList($allow);
    }
    elsif ( defined &Foswiki::Func::isGroup ) {
        my $thisUser = Foswiki::Func::getWikiName();
        foreach my $allowed ( split( /\s*,\s*/, $allow ) ) {
            ( my $waste, $allowed ) =
              Foswiki::Func::normalizeWebTopicName( undef, $allowed );
            if ( Foswiki::Func::isGroup($allowed) ) {
                return 1 if Foswiki::Func::isGroupMember( $allowed, $thisUser );
            }
            else {
                $allowed = Foswiki::Func::getWikiUserName($allowed);
                $allowed =~ s/^.*\.//;    # strip web
                return 1 if $thisUser eq $allowed;
            }
        }
    }
    return 0;
}

# Tag handler for WORKFLOWSUFFIX but is also used whenever the suffix is needed.
# Please do not change this function to return anything but the suffix.
# Returns the suffix that should be used.
sub _WORKFLOWSUFFIX {
    my $forkSuffix = $Foswiki::cfg{Extensions}{KVPPlugin}{suffix};
    if (not $forkSuffix) {
        $forkSuffix = 'TALK';
        Foswiki::Func::writeWarning("No Suffix defined! Defaulting to $forkSuffix!");
        _broadcast('%MAKETEXT{"No Suffix defined! Defaulting to [_1]!" args="'.$forkSuffix.'"}%');
    }
    return $forkSuffix;
}

sub _getOrigin {
    my ( $topic ) = @_;

    my $suffix = _WORKFLOWSUFFIX();
    if ($topic =~ /(.*)$suffix$/) {
        return $1;
    } else {
        return $topic;
    }
}

# Tag handler, returns the topicname without suffix
sub _WORKFLOWORIGIN {
    my ( $session, $attributes, $topic, $web ) = @_;

    return $originCache if !$attributes->{_DEFAULT} && defined $originCache;
    return _getOrigin( $attributes->{_DEFAULT} || $topic );
}

sub _initTOPIC {
    my ( $web, $topic, $rev, $meta, $forceNew ) = @_;

    # Skip system web for performance
    return undef if ($web eq "System");

    # Filter out topics inhibited in configure
    my $exceptions = $Foswiki::cfg{Extensions}{KVPPlugin}{except};
    return undef if $exceptions && $topic =~ /$exceptions/;

    $rev ||= MAXREV;    # latest

    ( $web, $topic ) = Foswiki::Func::normalizeWebTopicName( $web, $topic );
    return undef unless(Foswiki::Func::isValidWebName( $web ));

    my $controlledTopic;
    my $controlledTopicCID = "$web.$topic.$rev";

    unless ($forceNew) {
        $controlledTopic = $cache{$controlledTopicCID};
        if ($controlledTopic) {
            return if $controlledTopic eq '_undef';
            return $controlledTopic;
        }
    }

    return undef unless Foswiki::Func::isValidTopicName( $topic, 1 );

    if($Foswiki::Plugins::SESSION->{store}->can('isVirtualTopic')) {
        my $isVirtual;
        my $useVirtualTopics;
        if($meta) {
            $web = $meta->web();
            $topic = $meta->topic();
        }
        $isVirtual = $Foswiki::Plugins::SESSION->{store}->isVirtualTopic($web, $topic);
        $useVirtualTopics =
            Foswiki::Func::getPreferencesValue("KVP_USE_VIRTUAL_TOPIC", $web);
        if($isVirtual && !$useVirtualTopics) {
            $cache{$controlledTopicCID} = '_undef';
            return undef;
        }
    }

    my $workflowName;
    if ( $meta ) {
        # $meta->getPreference('WORKFLOW') does not necessarily do what I want,
        # eg. on a newly created topic it will return an empty string.
        # Unfortunately this won't cover a "   * Set WORKFLOW = ..."
        my $pref = $meta->get('PREFERENCE', 'WORKFLOW');
        $workflowName = $pref->{value} if $pref;
    }
    unless( defined $workflowName ) {
        # we need to clear any persisting setting, or we might get the value from the wrong web
        my $saved = Foswiki::Func::getPreferencesValue('WORKFLOW');
        Foswiki::Func::setPreferencesValue('WORKFLOW', undef) if $saved;

        Foswiki::Func::pushTopicContext( $web, $topic );
        $workflowName = Foswiki::Func::getPreferencesValue('WORKFLOW');
        Foswiki::Func::popTopicContext();

        Foswiki::Func::setPreferencesValue('WORKFLOW', $saved) if $saved;
    }

    if ($workflowName) {
        ( my $wfWeb, $workflowName ) =
          Foswiki::Func::normalizeWebTopicName( $web, $workflowName );

        my $workflowCID = "w:$wfWeb.$workflowName";
        my $workflow = $cache{$workflowCID};
        unless ( $workflow) {
            if ( Foswiki::Func::topicExists( $wfWeb, $workflowName ) ) {
                $workflow =
                  new Foswiki::Plugins::KVPPlugin::Workflow( $wfWeb,
                    $workflowName );
                $cache{$workflowCID} = $workflow;
            } else {
                Foswiki::Func::writeWarning("Workflow topic for $web.$topic does not exist: '$wfWeb.$workflowName'");
                _broadcast('%MAKETEXT{"Workflow topic for [_1] does not exist: &#39;[_2]&#39;" args="'."[[$web.$topic]], $wfWeb.$workflowName".'"}%');
            }
        }

        if ($workflow) {
            unless( $meta ) {
                ( $meta, undef ) =
                  Foswiki::Func::readTopic( $web, $topic, $rev );

                # Disable the lazy loader, omitting this may results in erroneous forked topics:
                $meta->loadVersion( ($rev ne MAXREV) ? $rev : undef ) unless $meta->getLoadedRev();
            } else {
                $meta->loadVersion() unless $meta->getLoadedRev(); # XXX Why do I have to loadVersion when I get a meta from beforeSaveHandler?
                                                                   # When omitting: Will get 2 %META:WORKFLOW{...}%
            }
            $controlledTopic =
              new Foswiki::Plugins::KVPPlugin::ControlledTopic(
                $workflow, $web, $topic, $meta );
        }
    }

    unless( $forceNew && $forceNew == NOCACHE ) {
        $cache{$controlledTopicCID} = $controlledTopic || '_undef';
    }
    return $controlledTopic;
}

sub _getTopicName {
    my ($attributes, $web, $topic) = @_;

    return Foswiki::Func::normalizeWebTopicName(
        $attributes->{web} || $web,
        $attributes->{_DEFAULT} || $topic
    );
}

# Tag handler
sub _WORKFLOWHISTORY {
    my ( $session, $attributes, $topic, $web ) = @_;

    ($web, $topic) = _getTopicName($attributes, $web, $topic);
    my $controlledTopic = _initTOPIC( $web, $topic );
    return '' unless $controlledTopic;

    return $controlledTopic->getHistoryText();
}

# When approved article is beeing renamed, rename talks as well.
sub afterRenameHandler {
    my ( $oldWeb, $oldTopic, $oldAttachment,
         $newWeb, $newTopic, $newAttachment ) = @_;

    return unless $oldTopic; # don't handle webs
    return if $oldAttachment; # nor attachments

    my $suffix = _WORKFLOWSUFFIX();
    return unless $suffix;

    if($oldTopic ne _getOrigin($oldTopic)) {
        # index workflow_hasdiscussion_b change
        _requestSolrUpdate("$oldWeb." . _getOrigin($oldTopic));
    }

    return if $isStateChange;

    my $oldDiscussion = "$oldTopic$suffix";
    return unless Foswiki::Func::topicExists($oldWeb, $oldDiscussion);

    my $newDiscussion = "$newTopic$suffix";
    # XXX what to do if there is already a discussion?!?
    if (Foswiki::Func::topicExists($newWeb, $newDiscussion)) {
        Foswiki::Func::writeWarning("Throwing existing discussion away ($newWeb.$newDiscussion) after renaming $oldWeb.$oldTopic to $newWeb.$newDiscussion!");
        _trashTopic($newWeb, $newDiscussion);
    }

    Foswiki::Func::moveTopic($oldWeb, $oldDiscussion, $newWeb, $newDiscussion);
}

sub _WORKFLOWGETREVFOR {
    my ( $session, $attributes, $topic, $web ) = @_;

    # TODO: get rev by version etc.

    my $name = $attributes->{name} || $attributes->{_DEFAULT};
    return '0' unless $name;
    my $nameRegExp = qr#^(?:$name)$#;

    my $skip = $attributes->{skip} || 0;

    my $rWeb = $attributes->{web} || $web;
    my $rTopic = $attributes->{topic} || $topic;

    my $rev = $attributes->{startrev};

    my $controlledTopic = _initTOPIC( $rWeb, $rTopic, $rev, undef, NOCACHE );
    return ((defined $attributes->{uncontrolled}) ? $attributes->{uncontrolled} : '0') unless $controlledTopic;

    unless (defined $rev) {
        my %info = $controlledTopic->{meta}->getRevisionInfo();
        $rev = $info{version} || 0;
    }

    my $version;
    if(defined $attributes->{version}) {
        $version = $attributes->{version};
        if($version =~ m#-(\d+)#) {
            $version = $controlledTopic->getWorkflowMeta('Revision') - $1; # if this becomes negative, we'll return 0 next
        }
        return '0' unless $version =~ m/^\d+$/;
    } else {
        $version = 99999999;
    }

    while((not ($controlledTopic->getState() =~ m#$nameRegExp# && $version >= $controlledTopic->getWorkflowMeta('Revision')) ) || $skip--) {
        unless(--$rev >= 0) {
            $rev = ((defined $attributes->{notfound}) ? $attributes->{notfound} : 0);
            last;
        }
        $controlledTopic = _initTOPIC( $rWeb, $rTopic, $rev, undef, NOCACHE );
    }
    return $rev;
}

sub WORKFLOWMETA {
    my ( $session, $attributes, $topic, $web ) = @_;

    my $rWeb = $attributes->{web} || $web;
    my $rTopic = $attributes->{topic} || $topic;
    my $rev = $attributes->{rev};
    my $alt = $attributes->{alt} || '';
    my $remove = $attributes->{nousersweb};
    my $timeformat = $attributes->{timeformat};
    if(!$rev) {
        my $request = Foswiki::Func::getRequestObject();
        $rev = $request->param("rev") || 0;
    }

    my $attr;
    my $controlledTopic = _initTOPIC( $rWeb, $rTopic, $rev );
    return $alt unless $controlledTopic;

    unless ($controlledTopic->getRow('approved')) {
        return $attributes->{exceptdiscussion} if $attributes->{exceptdiscussion};
    }

    if (!defined $attributes->{name}) {
        # Old interpretation, for compatibility
        $attr = $attributes->{_DEFAULT};
    } else {
        $attr = $attributes->{name};
    }
    $attr ||= 'name';

    # handle assigned
    if( $attr eq 'tasked' ) {
        my $tasked = $controlledTopic->getTaskedPeople();
        return '' unless $tasked;
        return join(',', @$tasked );
    } elsif( $attr =~ m/^(?:LASTPROCESSOR|LEAVING|LASTTIME)$/ ) {
        $attr = $attr . '_' . $controlledTopic->getWorkflowMeta('name');
    }

    my $ret = $controlledTopic->getWorkflowMeta($attr);
    if(!defined $ret) {
        my $list = $attributes->{or};
        if($list) {
            while(!defined $ret && $list =~ m/([a-zA-Z_]*)/g) {
                $ret = $controlledTopic->getWorkflowMeta($1);
            }
        }
    }
    if(defined $ret) {
        # remove UsersWeb
        $ret =~ s#^$Foswiki::cfg{UsersWebName}\.##g if $remove;

        # convert time format
        if($timeformat && $ret =~ m#(\d{1,2})\.(\d{1,2})\.(\d{4})#) {
            my $epoch = Foswiki::Time::parseTime("$3-$2-$1T");
            $ret = Foswiki::Time::formatTime($epoch, $timeformat);
        }

        return $ret;
    }
    return  $alt;
}

sub _WORKFLOWTRANSITIONVUE {
    my ( $session, $attributes, $topic, $web ) = @_;

    ($web, $topic) = _getTopicName($attributes, $web, $topic);
    my $controlledTopic = _initTOPIC( $web, $topic );
    return '' unless $controlledTopic;

    my $transitions = $controlledTopic->getTransitionAttributesArray(1);

    my $data = {
        web => $web,
        topic => $topic,
        current_state => $controlledTopic->getState(),
        current_state_display => $controlledTopic->getWorkflowMeta('displayname', undef, 0),
        message => $session->i18n->maketext( _GETWORKFLOWROW($session, {_DEFAULT => 'message', unescapeEntities => 1}, $topic, $web) ),
        actions => $transitions,
        origin => _getOrigin($topic),
    };

    Foswiki::Func::addToZone('script', 'WORKFLOW::VUE', <<SCRIPT, 'JQUERYPLUGIN::FOSWIKI,VUEJSPLUGIN,');
<script type="text/javascript" src="%PUBURLPATH%/%SYSTEMWEB%/KVPPlugin/vue-transitions.js?v=$RELEASE"></script>
SCRIPT

    my $clientToken = Foswiki::Plugins::VueJSPlugin::getClientToken();
    my $json = to_json($data);
    $json =~ s/([&<>%])/'&#'.ord($1).';'/ge;
    return <<HTML;
        <div class="KVPPlugin vue-transitions foswikiHidden" data-vue-client-token="$clientToken">
            <div class="json">$json</div>
            <form method="post" name="strikeonedummy"></form>
        </div>
HTML
}

# Tag handler
sub _WORKFLOWTRANSITION {
    my ( $session, $attributes, $topic, $web ) = @_;

    ($web, $topic) = _getTopicName($attributes, $web, $topic);
    my $controlledTopic = _initTOPIC( $web, $topic );
    return '' unless $controlledTopic;

    # Include JQuery.block
    Foswiki::Plugins::JQueryPlugin::createPlugin( 'blockUI', $session );

    #
    # Build the button to change the current status
    #
    my (@actions, $displayActions);
    my $numberOfActions;
    my $transwarn = {};
    my $cs = encode_entities($controlledTopic->getState(), $unsafe_chars);
    my $webtopic = encode_entities("$web.$topic", $unsafe_chars);

    # Get actions and warnings
    { # scope
        ( my $tmpActions, my $tmpWarnings, $displayActions ) = $controlledTopic->getActions();
        @actions         = @$tmpActions;
        $numberOfActions = scalar(@actions);
        my @warnings     = @$tmpWarnings;

        # build javascript to associate warnings with actions
        for( my $a = $numberOfActions-1; $a >= 0; $a-- ) {
            my $warning = $warnings[$a];
            next unless $warning;
            $warning = decode_entities($warning);
            $warning = Foswiki::Plugins::JSi18nPlugin::MAKETEXT($session, {string => $warning, literal => 1});
            next unless $warning;
            my $action = $actions[$a];
            $transwarn->{WORKFLOW}->{w}->{$action} = $warning;
        }
    }

    unless ($numberOfActions) {
        return '';
    }

    my @fields = ();
    push( @fields, "<input type='hidden' name='WORKFLOWSTATE' value='$cs' />");
    push( @fields, "<input type='hidden' name='topic' value='$webtopic' />");

    my ($allow, $suggest, $remark, $alreadyProposed, $unsatisfiedMandatory, $unsatisfiedMandatoryFields) = $controlledTopic->getTransitionAttributes();

    $transwarn->{WORKFLOW}{allowOption} = $allow;
    $transwarn->{WORKFLOW}{suggestOption} = $suggest;
    $transwarn->{WORKFLOW}{remarkOption} = $remark;
    $transwarn->{WORKFLOW}{alreadyProposed} = $alreadyProposed;
    $transwarn->{WORKFLOW}{unsatisfiedMandatory} = $unsatisfiedMandatory;
    $transwarn->{WORKFLOW}{unsatisfiedMandatoryFields} = $unsatisfiedMandatoryFields;
    my $json = to_json($transwarn);
    $json =~ s#%#<nop>%<nop>#g;

    Foswiki::Plugins::JSi18nPlugin::JSI18N($session, 'KVPPlugin', 'transitions');
    Foswiki::Func::addToZone('script', 'WORKFLOW::COMMENT', <<SCRIPT, 'JQUERYPLUGIN::FOSWIKI');
<script type="text/json" class="KVPPlugin_WORKFLOW">$json</script>
<script type="text/javascript" src="%PUBURLPATH%/%SYSTEMWEB%/KVPPlugin/transitions.js?version=$VERSION"></script>
SCRIPT

    if ( $numberOfActions == 1 ) {
        my $action = $actions[0];
        $action =~ s#"#&quot;#g;
        $action =~ s#'#&\#39;#g;
        $action =~ s#%#&\#37;#g;
        my $displayAction = $displayActions->[0];
        push( @fields,
            "<input type='hidden' name='WORKFLOWACTION' value='$action' />" );
        push(
            @fields,
            "<noautolink>%BUTTON{\"$displayAction\" id=\"WORKFLOWbutton\" type=\"submit\"}%</noautolink>"
        );
    }
    else {
        push( @fields, "<select name='WORKFLOWACTION' id='WORKFLOWmenu' style='float: left'>");

        # first one is special, because it must be selected
        my $firstAction = shift @actions;
        my $firstActionDisplay = shift @$displayActions;
        push( @fields, "<option selected='selected' value='" . encode_entities($firstAction, $unsafe_chars) . "'>$firstActionDisplay</option>" );
        # now the rest
        foreach my $i ( 0 .. $#actions ) {
            my $action = $actions[$i];
            my $displayAction = $displayActions->[$i];
            push( @fields, "<option value='" . encode_entities($action, $unsafe_chars) . "'>$displayAction</option>" );
        };
        push( @fields, "</select>");
        push(
            @fields,
            '<noautolink>%BUTTON{"%MAKETEXT{"Change status"}%" type="submit" class="KVPChangeStatus"}%</noautolink>'
        );
    }

    push( @fields,
          "<span style=\"display: none;\" id=\"WORKFLOWchkbox\"><label><input type='checkbox' value='1' name='removeComments' id='WORKFLOWchkboxbox'>"
          . encode_entities(Foswiki::Func::expandCommonVariables('%MAKETEXT{"delete comments"}%'), $unsafe_chars)
          . "</label></span>"
    );

    push( @fields, '<br style="clear: left;" />' );
    my $msg = $controlledTopic->getWorkflowPreference('KVP_MESSAGE_ALREADY_PROPOSED') || 'A decision has already been made for your areas of responsibility, either by yourself or by another user.';
    push( @fields,
          "<div style=\"display: none;\" id=\"WORKFLOWalreadyProposedLabel\">%MAKETEXT{\"$msg\"}%</div>"
    );

    push( @fields,
        '<div style="display: none" id="KVPRemark">%MAKETEXT{"Remarks"}%:<br /><textarea name="message" cols="50" rows="3" ></textarea></div>'
    );


    my $url = Foswiki::Func::getScriptUrl(
        $pluginName, 'changeState', 'rest'
    );

    unshift( @fields, "<form method='post' action='$url' class='KVPTransitionForm'>" );
    push( @fields, '</form>' );

    return join('', @fields);
}

# Tag handler
# Returns the state of the current topic.
sub WORKFLOWSTATE {
    my ( $session, $attributes, $topic, $web ) = @_;

    ($web, $topic) = _getTopicName($attributes, $web, $topic);
    my $controlledTopic = _initTOPIC( $web, $topic );

    return '' unless $controlledTopic;
    return $controlledTopic->getState();
}

# Tag handler
sub _WORKFLOWFORK {
    my ( $session, $attributes, $topic, $web ) = @_;

    $web = $attributes->{web} || $web;
    $topic = $attributes->{topic} || $topic;

    my $controlledTopic = _initTOPIC( $web, $topic );
    return ($attributes->{uncontrolled} || '') unless $controlledTopic;

    #Check we can fork
    my ($action, $warning) = @{$controlledTopic->canFork()};
    return ($attributes->{cannotfork} || '') unless $action;

    $warning = '' unless defined $warning;
    $warning = encode_entities($warning, $unsafe_chars);

    my $newnames;
    if (!defined $attributes->{newnames}) {
        # Old interpretation, for compatibility
        $newnames = $attributes->{_DEFAULT};
        $topic = $attributes->{topic} || $topic;
    } else {
        ($web, $topic) = _getTopicName($attributes, $web, $topic);
        $newnames = $attributes->{newnames};
    }

    if (!Foswiki::Func::topicExists($web, $topic)) {
        return "";
        return "<span class='foswikiAlert'>WORKFLOWFORK: '$topic' does not exist</span>";
    }

    my $label = $attributes->{label} || "%MAKETEXT{$action}%";
    my $title = $attributes->{title};
    $title = ($title)?"title='$title'":'';

    my $url;
    if ( $newnames ) {
        $url = Foswiki::Func::getScriptUrl( 'KVPPlugin', 'fork', 'restauth', topic => "$web.$topic", newnames => $newnames );
    } else {
        $url = Foswiki::Func::getScriptUrl( 'KVPPlugin', 'fork', 'restauth', topic => "$web.$topic" );
    }

    # Add script to prevent double-clicking link
    my $js = Foswiki::Func::getPubUrlPath()."/$Foswiki::cfg{SystemWebName}/KVPPlugin/blockLink.js?version=$VERSION";
    Foswiki::Func::addToZone('script', 'WORKFLOW::DISABLE', "<script type=\"text/javascript\" src=\"$js\"></script>", 'JQUERYPLUGIN::FOSWIKI');
    Foswiki::Plugins::JQueryPlugin::createPlugin( 'blockUI', $session );

    return "<a class=\"kvpForkLink\" warning=\"$warning\" href='$url' $title>$label</a>";
}

# Tag handler
# Return the entry of the given row for the current topic in it's current state.
sub _GETWORKFLOWROW {
    my ( $session, $attributes, $topic, $web ) = @_;
    my $param = $attributes->{_DEFAULT};
    my $rev = $attributes->{rev};
    # XXX If $aweb.$atopic does not exist defaultstate will be assumed
    my $atopic = $attributes->{topic} || $topic;
    my $aweb = $attributes->{web} || $web;

    my $controlledTopic = _initTOPIC ($aweb, $atopic, $rev );
    return $controlledTopic->getRow( $param, $attributes->{unescapeEntities} ) if $controlledTopic;

    # Not cotrolled get row from values in configure
    my $configure = $Foswiki::cfg{Extensions}{KVPPlugin}{uncontrolledRow};
    return '' unless ref($configure) eq 'HASH';
    return $configure->{$param} || '';
}

# Tag handler
# For a given state, return information about any outstanding
# (percentage-based) transitions, including who has already signed off on the
# transition and which of the 'allowed' entries they represent.
# Information is returned in JSON format.
sub _WORKFLOWPROPONENTS {
    my ($session, $params, $topic, $web) = @_;
    my $state = $params->{state};
    my $action = $params->{action};
    my $ptopic = $params->{topic} || $topic;
    my $pweb = $params->{web} || $web;

    my $controlledTopic = _initTOPIC($pweb, $ptopic);
    return 'null' unless $controlledTopic;
    if ($action) {
        return to_json($controlledTopic->mapProponentsToAllowed($action));
    }
    my ($actions) = $controlledTopic->getActions;
    return to_json({map { $_, $controlledTopic->mapProponentsToAllowed($_) }
        grep { $controlledTopic->isProposableTransition($_) } @$actions});
}

# Will find a topic in trashweb to move $web.$topic to by adding a numbered suffix.
sub _trashTopic {
    my ($web, $topic) = @_;

    my $trashWeb = $Foswiki::cfg{TrashWebName};

    my $trashTopic = $web . $topic;
    $trashTopic =~ s#/|\.##g; # remove subweb-deliminators

    my $numberedTrashTopic = $trashTopic;
    my $i = 1;
    while (Foswiki::Func::topicExists($trashWeb, $numberedTrashTopic)) {
        $numberedTrashTopic = $trashTopic."_$i";
        $i++;
    }

    Foswiki::Func::moveTopic( $web, $topic, $trashWeb, $numberedTrashTopic );
}

# Handle actions. REST handler, on changeState action.
sub _changeState {
    my ($session) = @_;

    my $query = Foswiki::Func::getCgiQuery();

    return unless $query;

    my $mails = [];

    my $json = $query->param('json');
    my $response;

    try {
        my $report = transitionTopic($session, {
            web => $query->param('web') || $session->{webName},
            topic => $query->param('topic') || $session->{topicName},
            action => $query->param('WORKFLOWACTION') || '',
            state => $query->param('WORKFLOWSTATE') || '',
            mails => $mails,
            remark => $query->param('message') || '',
            removeComments => $query->param('remove_comments') || '0',
            breakLock => $query->param('breaklock') || 0,
            actionDisplayname => $query->param('action_displayname') || '',
            currentStateDisplayname => $query->param('current_state_displayname') || '',
        });
        foreach my $mail ( @$mails ) {
            sendKVPMail($mail);
        }
        if ($json) {
            $response = to_json({status => 'ok'});
            return;
        }

        my $url = $report->{url};
        if($query->param('redirectto')) {
            my ($redirectWeb, $redirectTopic) = Foswiki::Func::normalizeWebTopicName(undef, $query->param('redirectto'));
            $url = Foswiki::Func::getViewUrl($redirectWeb, $redirectTopic) if Foswiki::Func::topicExists($redirectWeb, $redirectTopic);
        }
        Foswiki::Func::redirectCgiQuery( undef, $url ) if $url;
    } catch Foswiki::OopsException with {
        my $e = shift;
        if ($json) {
            $response = to_json({status => 'error', data => $e->{json}, msg => $e->stringify});
            return;
        }
        $e->generate($session);
    };

    return $response;
}

# Will transition a topic.
# Throws an OopsException when anything goes wrong.
# Returns a url the user should go to next (to the transitioned topic, or the
# parent if the topic was discarded).
#
# Parameters:
#    you can pass parameters in a list (depricated) or pass in an options ref:
#    transitionTopic($sesson, { web => ...})
#
#    * web: web of the topic
#    * topic: topic name
#    * action: The transition to be performed
#    * state: The _current_ state of the topic
#    * mail: an array transition emails can be pushed on, leave undef to have
#       them sent immediately
#    * remark: remark for the transition
#    * removeComments: set to 1 if MetaComments should be deleted
#    * breaklock: set to 1 to clear any lease
#    * noFork: actions with FORK attribute will not automatically fork if this is true
sub transitionTopic {
    my $session = shift;
    my ($web, $topic, $action, $state, $mails, $remark, $removeComments, $breaklock, $noFork, $actionDisplayname, $currentStateDisplayname);
    if(ref($_[0])) {
        my $options = $_[0];
        $web = $options->{web};
        $topic = $options->{topic};
        $action = $options->{action};
        $state = $options->{state};
        $mails = $options->{mails};
        $remark = $options->{remark};
        $removeComments = $options->{removeComments};
        $breaklock = $options->{breaklock};
        $noFork = $options->{noFork};
        $actionDisplayname = $options->{actionDisplayname};
        $currentStateDisplayname = $options->{currentStateDisplayname};
    } else {
        # old style
        ($web, $topic, $action, $state, $mails, $remark, $removeComments, $breaklock, $noFork) = @_;
    }

    ($web, $topic) =
      Foswiki::Func::normalizeWebTopicName( $web, $topic );

    die unless $web && $topic;

    my $url;
    my $controlledTopic = _initTOPIC( $web, $topic );

    unless ($controlledTopic && Foswiki::Func::topicExists( $web, $topic )) {
        throw Foswiki::OopsException(
            "oopswrkflwsaveerr",
            web => $web,
            topic => $topic,
            def => 'TopicNotFound',
            params => [],
        );
    }

    my $oldIsApproved = $controlledTopic->getRow( "approved" );

    unless ($action && $state) {
        throw Foswiki::OopsException(
            "oopswrkflwsaveerr",
            web => $web,
            topic => $topic,
            def => 'MissingParameter',
            params => [$state || '', $action || ''],
            json => { type => 'MissingParameter' }
        );
    }
    unless ($state eq $controlledTopic->getState()) {
        my $assumedStateDisplayname = $currentStateDisplayname || $state;

        throw Foswiki::OopsException(
            "oopswrkflwsaveerr",
            web => $web,
            topic => $topic,
            def => 'WrongState',
            params => [
                decode_entities($controlledTopic->getWorkflowMeta('displayname')),
                decode_entities($assumedStateDisplayname),
                $controlledTopic->getState(),
                $state,
            ],
            json => {
                type => 'WrongState',
                actual_state => $controlledTopic->getState,
                actual_state_displayname => $controlledTopic->getWorkflowMeta('displayname'),
                assumed_state => $state,
                assumed_state_displayname => $assumedStateDisplayname
            },
        );
    }
    unless ($controlledTopic->haveNextState($action)) {
        my $displayState = $controlledTopic->getWorkflowMeta('displayname');
        my $displayAction = $actionDisplayname || $action;

        throw Foswiki::OopsException(
            "oopswrkflwsaveerr",
            web => $web,
            topic => $topic,
            def => 'NoNextState',
            params => [
                decode_entities($displayState),
                decode_entities($displayAction),
                $state,
                $action,
            ],
            json => {
                type => 'NoNextState',
                state => $state,
                action => $action ,
                state_displayname => $displayState,
                action_displayname => $displayAction
            },
        );
    }
    $removeComments = '0' unless defined $removeComments;

    # Check that no-one else has a lease on the topic
    unless (Foswiki::Func::isTrue($breaklock)) {
        my ( $url, $loginName, $t ) = Foswiki::Func::checkTopicEditLock(
            $web, $topic
        );
        if ( $t ) {
            my $currUser = Foswiki::Func::getCanonicalUserID();
            my $locker = Foswiki::Func::getCanonicalUserID($loginName);
            if ($locker ne $currUser) {
                $t = Foswiki::Time::formatDelta(
                    $t*60, $Foswiki::Plugins::SESSION->i18n
                );
                $remark ||= '';
                $remark =~ s#"#&quot;#;
                throw Foswiki::OopsException(
                    'oopswfplease',
                    web => $web,
                    topic => $topic,
                    params => [Foswiki::Func::getWikiName($locker), "$web.$topic", $t, $state, $action, $remark, $removeComments ],
                    json => { type => 'LeaseOtherUser', locker => $locker, remaining_minutes => $t }
                );
            }
        }
    }

    my $appTopic = _getOrigin($topic); # do not fallback on originCache, this might be called from another plugin
    my $appWeb = $web;
    try {
        $url = Foswiki::Func::getScriptUrl( $web, $topic, 'view' );

        my $actionAttributes = $controlledTopic->getAttributes($action) || '';

        my $saved;

        if ($actionAttributes =~ m#\bALLOWEDPERCENT\((\d+)\)(?:\W|$)#) {
            my $percent = $1;
            # TODO: ACL checks are not enforced on proposals, so anyone who
            # proposes the transaction (e.g. admins) will be added to the
            # list, though they should still be ignored in the calculations.
            # We may need to throw an exception here if the user is not a
            # valid potential proponent.
            $controlledTopic->addTransitionProponent($action); # just hope for the best
            my @props = $controlledTopic->getTransitionProponents($action);
            my %allowed2props = %{ $controlledTopic->mapProponentsToAllowed($action) };
            my $num_allowed = scalar values %allowed2props;
            my $num_done = scalar grep { defined $_ } values %allowed2props;
            my $current_percent = $num_allowed ? $num_done / $num_allowed * 100 : 100; # when the column is empty ($num_allowed == 0), everyone should be able to do the transition ($current_percent = 100)

            if ($current_percent < $percent) {
                $controlledTopic->save(1);
                return {
                    url => $url,
                };
            }
        }

        # Create copy if this is a fork
        if( !$noFork && $actionAttributes =~ m#(?:\W|^)(?:SELECTABLE)?FORK((?:\((?:".*?")?[^)]*\))?)(?:\W|$)# ) {
            my $params = $1;

            $appTopic .= _WORKFLOWSUFFIX();
            if($params) {
                if( $params =~ s#^\s*\(\s*"(.*?)"\s*## ) {
                    $appTopic = $1;
                }
                if( $params =~ s#topic="(.*?)"\s*## ) {
                    $appTopic = $1;
                }
                if( $params =~ s#web="(.*?)"\s*## ) {
                    $appWeb = $1;
                }
            }
            if($actionAttributes =~ m#SETREV\(\s*version\s*=\s*\"(\d+[.,]?\d*)(?<!\\)\"\s*\)#) {
                $controlledTopic->setRev( $1 );
            }

            if ( Foswiki::Func::topicExists($appWeb, $appTopic) && $appTopic !~ m#AUTOINC\d+# ) {
                throw Error::Simple('%MAKETEXT{"Forked topic exists: [_1]" args="'."$appWeb.$appTopic".'"}%');
            }

            $saved = _pushParams( $params );
            $controlledTopic = _createForkedCopy($session, $controlledTopic->{meta}, $appWeb, $appTopic);
            $appTopic = $controlledTopic->{topic};

            $url = Foswiki::Func::getScriptUrl( $appWeb, $appTopic, 'view' );
        }

        if( $actionAttributes =~ m/(?:\W|^)CLEARMETA((?:\((?:".*?")?[^)]*\))?)(?:\W|$)/ ) {
            my $params = $1;
            if($params && $params =~ m#\s*"(.*?)"\s*# ) {
                    $params = $1;
            }

            $controlledTopic->clearWorkflowMeta( $params );
        }

        # clear message, if workflow doesn't allow it (maybe the
        # user entered a message and then switched state...)
        if( $actionAttributes !~ /(?:\W|^)REMARK(?:\W|$)/ ) {
            $remark = '';
        }

        # check if deleting comments is allowed if requested
        if($removeComments) {
            my $transitionAttributes = $controlledTopic->getTransitionAttributesArray();
            my $isAllowed;
            foreach my $eachTransition ( @$transitionAttributes ) {
                next unless $eachTransition->{allow_delete_comments} || $eachTransition->{suggest_delete_comments};
                next unless $eachTransition->{action} eq $action;
                $isAllowed = 1;
                last;
            }
            unless($isAllowed) {
                # this can happen by changing the popup-menue after
                # selecting the checkbox
                $removeComments = '0';
            }
        }
        # overwrite user-choice if workflow demands it
        if($controlledTopic->isRemovingComments($state, $action)) {
            $removeComments = '1';
        }
        removeComments($controlledTopic) if ($removeComments eq '1');

        # Do the actual transition
        my $mail = $controlledTopic->changeState($action, $remark);

        _popParams( $saved ) if $saved;

        # Our transition worked, do the chained transitions now
        while( $actionAttributes =~ m/\G.*?(?<!\w)CHAIN\s*\(\s*/g ) {
            my $options = {
                web => $web,
                topic => $appTopic
            };
            my ($name, $val);
            while($actionAttributes !~ m/\G\)/gc) {
                unless( $actionAttributes =~ m/\G([a-z]+)\s*=\s*"(.*?)(?<!\\)"\s*/gc ) {
                    my $err = "Error while parsing attributes '$actionAttributes' for $web.$topic in state '$state' for action '$action'";
                    Foswiki::Func::writeWarning($err);
                    throw Foswiki::OopsException(
                        'oopswrkflwsaveerr',
                        web => $web,
                        topic => $topic,
                        def => 'WorkflowParseErr',
                        params => [ $err ],
                        json => { type => 'WorkflowParseError', error => $err }
                    );
                }
                $name = $1;
                $val = $2;
                $val =~ s#\\"#"#g;
                $options->{$name} = $val;
            }
            my $other = _initTOPIC( $options->{web}, $options->{topic} );
            my $otherState;
            $otherState = $other->getState() if $other;
            try {
                transitionTopic($session, $options->{web}, $options->{topic}, $options->{action}, $otherState, $mails, $options->{remark}, $options->{removecomments}, $options->{breaklock} || $breaklock, 1);
            } catch Foswiki::OopsException with {
                my $e = shift;

                if($e->{template} eq 'oopswfplease') {
                    # We need to rethrow with _this_ transition, or a click on 'transition anyway' will only transition the chained one.
                    throw Foswiki::OopsException(
                        'oopswfplease',
                        web => $appWeb,
                        topic => $appTopic,
                        params => [$e->{params}->[0], $e->{params}->[1], $e->{params}->[2], $state, $action, $remark, $removeComments ],
                        json => { type => 'LeaseOtherUserChained', locker => $e->{params}[0], webtopic => $e->{params}[1], remaining_minutes => $e->{params}[2] }
                    );
                } else {
                    throw $e;
                }
            };
        }

        if($actionAttributes =~ m#SYNCREV\(\s*topic\s*=\s*\"(.*?)(?<!\\)\"\s*\)#) {
            my $otherWebTopic = $1;
            my $webParam = (($otherWebTopic =~ m#[./]#) ? undef : $web); # default to current web
            my $synced;
            my ($otherWeb, $otherTopic) = Foswiki::Func::normalizeWebTopicName( $webParam, $otherWebTopic );
            my $otherControlledTopic = _initTOPIC( $otherWeb, $otherTopic );
            if( $otherControlledTopic ) {
                $synced = $otherControlledTopic->getWorkflowMeta( 'Revision' );
            } else {
                Foswiki::Func::writeWarning("Could not SYNCREV $web.$topic to $otherWeb.$otherTopic");
            }
            $synced ||= 0;
            $controlledTopic->setRev( $synced );
        }
        # Flag that this is a state change to the beforeSaveHandler (beforeRenameHandler)
        local $isStateChange = 1;
        # because we disabled the beforeSaveHandler, we must make sure, that there are no stub markers left (this might be a "Put under CIP" transition)
        $controlledTopic->{meta}->remove('PREFERENCE', 'WorkflowStub');

        # Hier Action
        if ($actionAttributes =~ m#(?:\W|^)DISCARD(\W|$)#) {
            $controlledTopic->purgeContributors(); # XXX Wirklich?
            my $origMeta = $controlledTopic->{meta};

            # Move topic to trash
            $controlledTopic->save(1);
            _trashTopic($web, $topic);

            # Only unlock / add to history if web exists (does not when topic)
            if(Foswiki::Func::topicExists( $web, $appTopic )) {
                $url = Foswiki::Func::getScriptUrl( $web, $appTopic, 'view' );
            } else {
                # if non-talk topic does not exist redirect to parent
                my $parent = $origMeta->getParent();
                my $parentWeb = $origMeta->web();
                $url = Foswiki::Func::getViewUrl($parentWeb, $parent);
            }
        }
        elsif(my $destinationWeb = _extractDestinationWebFromMoveAttribute($actionAttributes)){
            if($appTopic ne $controlledTopic->{topic}){
                Foswiki::Func::moveTopic($controlledTopic->{web}, $appTopic, $destinationWeb, $appTopic);
            }
            $controlledTopic->moveTopic($destinationWeb, $controlledTopic->{topic});
            $controlledTopic->save(1);

            Foswiki::Plugins::ModacHelpersPlugin::updateTopicLinks($web, $appTopic, $destinationWeb, $appTopic);

            $url = Foswiki::Func::getViewUrl($controlledTopic->{web}, $controlledTopic->{topic});
        }
        # Check if discussion is beeing accepted
        elsif (!$oldIsApproved && $controlledTopic->getRow("approved") && $actionAttributes !~ m#(?:\W|^)FORK(?:\W|$)#) {
            # transfer ACLs from old document to new
            transferACL($web, $appTopic, $controlledTopic);
            $controlledTopic->purgeContributors();
            $controlledTopic->nextRev() unless $actionAttributes =~ m#NOREV|SYNCREV#;
            # Will save changes after moving original topic away

            $url = Foswiki::Func::getScriptUrl( $web, $appTopic, 'view' );

            #Alex: Force new Revision, damit Aenderungen auf jeden Fall in der History sichtbar werden
            # only move topic if it has a talk suffix
            if($appTopic eq $topic) {
                $controlledTopic->save(1);
            } else {
                #Zuerst kommt das alte Topic in den Muell, dann wird das neue verschoben
                _trashTopic($web, $appTopic);
                # Save now that I know i can move it afterwards
                $controlledTopic->save(1);

                # clear cached approved version
                my $rev = MAXREV;
                my $controlledTopicCID = "$web.$appTopic.$rev";
                undef $cache{$controlledTopicCID};

                $controlledTopic->moveTopic( $web, $appTopic );

                # update mail
                $mail->{options}->{webtopic} = "$web.$appTopic"; # XXX this should be handled by ControlledTopic
            }
        }
        else{
            $controlledTopic->nextRev() if $actionAttributes =~ m#NEXTREV#;
            $controlledTopic->save(1);
        }
        local $isStateChange = 0;

        # Add mails to stack, after CHAINed transitions have been executed and topics
        # have been moved.
        if($mails) {
            unshift(@$mails, $mail);
        } else {
            sendKVPMail($mail);
        }
    } catch Error::Simple with {
        my $error = shift;
        throw Foswiki::OopsException(
            'oopssaveerr',
            def => 'generic',
            web => $web,
            topic => $topic,
            params => [ $error || '?' ],
            json => { type => 'GenericError', error => $error || '?' }
           );
    };

    return { url => $url, webAfterTransition => $web, topicAfterTransition => $appTopic };
}

sub _extractDestinationWebFromMoveAttribute {
    my $attributes = shift;
    my ($destinationWeb) = ($attributes =~ /\bMOVE\((.+)\)(?:\W|$)/);

    return $destinationWeb;
}

# Forces write permission
sub transferACL {
    my ($srcWeb, $srcTopic, $dst) = @_;

    my ($srcMeta, $srcText) = Foswiki::Func::readTopic($srcWeb, $srcTopic);
    my $acl = '';
    if ( $srcMeta ) {
        my $hash = $srcMeta->get("PREFERENCE", "ALLOWTOPICCHANGE");
        if ( $hash ) {
            $acl = $hash->{"value"};
        }
    }

    if ($acl) {
        $dst->{meta}->putKeyed( 'PREFERENCE', { name => "ALLOWTOPICCHANGE", value => $acl } );
    } else {
        $dst->{meta}->remove("PREFERENCE", "ALLOWTOPICCHANGE");
    }
}

# Removes all comments (from MetacommentPlugin)
sub removeComments {
     my ($controlledTopic) = @_;
     $controlledTopic->{meta}->remove("COMMENT");
}

# Will redirect to article and warn if it has changed since link was created.
sub _restLink {
    my ($session, $plugin, $verb, $response) = @_;
    my $query = Foswiki::Func::getCgiQuery();
    my $state = $query->param( 'state' );
    my $webtopic = $query->param( 'webtopic' );

    my $url;

    my ($web, $topic) = Foswiki::Func::normalizeWebTopicName( undef, $webtopic );
    unless( $webtopic and $state and $web and $topic ) {
        Foswiki::Func::writeWarning("Wrong parameters for link: webtopici='$webtopic' state='$state'.");
        $url = Foswiki::Func::getScriptUrl(
            'Unknown', 'Unkown', 'oops',
            template => "oopsworkflowlink"
        );
    } elsif ( Foswiki::Func::topicExists( $web, $topic ) ) {
        # Check if article is still in correct state
        my ( $meta, $text ) = Foswiki::Func::readTopic( $web, $topic );
        my $wrkflw = $meta->get( 'WORKFLOW' );
        if ( $wrkflw && $wrkflw->{name} eq $state ) {
            # states are equal, redirecting to topic...
            my $origin = _getOrigin($topic);
            if($topic ne $origin && $query->param( 'compare' )) {
                $url = Foswiki::Func::getScriptUrl($web, $topic, 'compare', external => $origin, allowtransition => 1);
            } else {
                $url = Foswiki::Func::getViewUrl($web, $topic);
            }
        } else {
            $url = Foswiki::Func::getScriptUrl(
                $web, $topic, 'oops',
                template => "oopsworkflowchanged",
                param1   => 'changed',
                param2   => $state || '-',
                param3   => $wrkflw->{name} || '-',
            );
        }
    } else {
        # Try looking for origin
        my $origin = _getOrigin( $topic );
        if ( $origin ne $topic && Foswiki::Func::topicExists( $web, $origin ) ) {
            $url = Foswiki::Func::getScriptUrl(
                $web, $origin, 'oops',
                template => "oopsworkflowmoved",
                found    => "1"
            );
        } else {
            $url = Foswiki::Func::getScriptUrl(
                $web, 'WebHome', 'oops', # XXX does webhome always exist? What if web doesn't exist?
                template => "oopsworkflowmoved"
            );
        }
    }
    return $response->redirect($url);
}

sub _pushParams {
    my ( $params ) = @_;

    return undef unless $params =~ m#^with#gc;
    my $saved = [];
    while($params =~ m#\G\s+(\w+)\s*=\s*("|')(.*?)\2#gc) {
        my ($param, $value) = ($1, $3);

        push(@$saved, $param);
        push(@$saved, Foswiki::Func::getPreferencesValue($param));

        Foswiki::Func::setPreferencesValue($param, $value);
    }
    return undef if $params =~ m#\G\s*\S#gc;
    return $saved;
}

sub _popParams {
    my ( $saved ) = @_;
    while( scalar @$saved gt 1 ) {
        my $param = pop(@$saved);
        my $value = pop(@$saved);
        $value = '' unless defined $value;
        Foswiki::Func::setPreferencesValue($param, $value);
    }
}

sub _restHistory {
    my ($session, $plugin, $verb, $response) = @_;

    my $result = {};
    my $query = Foswiki::Func::getCgiQuery();
    my $webTopic = $query->param('topic');
    my $startFromVersion = $query->param('startFromVersion');
    my $pageSize = $query->param('size') || 5;
    my $restartWithFork = $query->param('restartWithFork') || 1;
    my $onlyIncludeTransitions = Foswiki::Func::isTrue($query->param('onlyIncludeTransitions'));

    my ($web, $topic) = Foswiki::Func::normalizeWebTopicName( undef, $webTopic );

    if ( !Foswiki::Func::topicExists( $web, $topic ) ) {
        $response->status(400);
        $result = {"message" => "Topic does not exist: $webTopic"};
        return to_json($result);
    }

    my $currentUserWikiName = Foswiki::Func::getWikiName();
    if(!Foswiki::Func::checkAccessPermission('VIEW', $currentUserWikiName, undef, $topic, $web)) {
        $response->status(400);
        $result = {"message" => "User not allowed to view history"};
        return to_json($result);
    }

    my $controlledTopic = _initTOPIC( $web, $topic );
    if(!$controlledTopic) {
        $response->status(400);
        $result = {"message" => "Topic not under any workflow"};
        return to_json($result);
    }

    my @historyEntries;
    my $hasMoreEntries = 1;

    my ( undef, undef, $lastVersion ) = $controlledTopic->{meta}->getRevisionInfo();
    my $start;
    if($startFromVersion) {
        $start = $startFromVersion -1;
    } else {
        $start = $lastVersion;
    }
    foreach my $version (reverse 1 .. $start) {
        $controlledTopic = _initTOPIC( $web, $topic, $version );
        if($controlledTopic->changedStateFromLastVersion()) {
            my $transition = $controlledTopic->getTransitionInfos();
            $transition->{type} = "transition";
            push @historyEntries, $transition;
        } elsif(!$onlyIncludeTransitions) {
            my $transition = $controlledTopic->getTransitionInfos();
            delete $transition->{icon};
            $transition->{type} = "save";
            push @historyEntries, $transition;
        }
        if($restartWithFork && $historyEntries[-1] && $historyEntries[-1]->{isFork}){
            $hasMoreEntries = 0;
            last;
        }
        if($version <= 1) {
            $hasMoreEntries = 0;
        }
        if(scalar @historyEntries >= $pageSize) {
            last;
        }
    }

    $result = {
        historyEntries => \@historyEntries,
        hasMoreEntries => $hasMoreEntries,
    };

    return to_json($result);
}

sub _restFork {
    my ($session, $plugin, $verb, $response) = @_;
    # Update the history in the template topic and the new topic
    my $query = Foswiki::Func::getCgiQuery();
    my $forkTopic = $query->param('topic');
    my @newnames = split(/,/, $query->param('newnames') || $forkTopic.(_WORKFLOWSUFFIX()));

    my $erroneous = '';
    my $mails = [];

    (my $forkWeb, $forkTopic) =
      Foswiki::Func::normalizeWebTopicName( undef, $forkTopic );
    my ($directToWeb, $directToTopic) = ($forkWeb, $forkTopic); # will be updated with forked topics

    my $controlledTopic;

    if ( Foswiki::Func::topicExists( $forkWeb, $forkTopic ) ) {
        # Validated
        $forkWeb =
          Foswiki::Sandbox::untaintUnchecked( $forkWeb );
        $forkTopic =
          Foswiki::Sandbox::untaintUnchecked( $forkTopic );
        $controlledTopic = _initTOPIC( $forkWeb, $forkTopic );
    } else {
        $erroneous = '%MAKETEXT{"Topic to fork from does not exist:"}% '."$forkWeb.$forkTopic";
    }

    unless($controlledTopic) {
        $erroneous = '%MAKETEXT{"Tried to fork from a topic, which is not under any workflow:"}% '."$forkWeb.$forkTopic" unless $erroneous;
    } else {
        my ($defaultAction, undef) = @{$controlledTopic->getActionWithAttribute('FORK')};

        my $ttmeta = $controlledTopic->{meta};

        # Default to topicTALKSUFFIX if no newnames are given, the action is valid.
        if ( scalar @newnames == 0 ) {
            my $forkSuffix = _WORKFLOWSUFFIX();
            @newnames = ($forkTopic.$forkSuffix);
        }

        my (@webs, @topics, @actions, @params) = ((), (), (), ());

        # First find out topicnames and actions.
        # In case of an error return without having changed anything in the wiki.
        foreach my $newname (@newnames) {

            # Get name for new topic and action to execute
            my ($newWeb, $newTopic, $newAction, $withParams);
            if ( $newname =~ m#^\s*$# ) {
                $erroneous .= "\n" . '%MAKETEXT{"Missing a destination to fork to (newname is empty)."}%' . "\n\n" unless $query->param('skipempty');
                next;
            } elsif ( $newname =~ m/^\s*\[(.+)\]\[(.+)\]\s*(.*?)\s*$/ ) {
                ($newTopic, $newAction, $withParams) = ($1, $2, $3);
                ($newWeb, $newTopic) = Foswiki::Func::normalizeWebTopicName( $forkWeb, $newTopic );
                unless (
                        Foswiki::Func::isValidTopicName( $newTopic, 1 ) &&
                        Foswiki::Func::isValidWebName( $newWeb ) ) {
                    $erroneous .= "\n" . '%MAKETEXT{"Invalid destination to fork to: [_1]" args="'."'$newWeb.$newTopic'\"}%\n\n";
                    next;
                }
                unless ( $controlledTopic->haveNextState($newAction) ) {
                    $erroneous .= "\n" . '%MAKETEXT{"Cannot execute transition =[_1]= on =[_2]= (invalid on source-workflow)." args="'."$newAction, $forkWeb.$forkTopic\"}%\n\n";
                    next;
                }
                my $saved;
                if($withParams) {
                    $saved = _pushParams( $withParams );
                    unless ( $saved) {
                        $erroneous .= '%MAKETEXT{"Could not parse parameters: \"[_1]\"" args="' . $withParams . '"}%' . "\n\n";
                        next;
                    }
                }
                # check if action allowed in targetworkflow
                my $targetControlledTopic = _initTOPIC( $newWeb, $newTopic, undef, $ttmeta, FORCENEW );
                unless( $targetControlledTopic && $targetControlledTopic->haveNextState($newAction) ) {
                    $erroneous .= '%MAKETEXT{"Cannot execute transition =[_1]= on =[_2]= (invalid on target-workflow)." args="'."$newAction, $newWeb.$newTopic\"}%\n\n";
                    next;
                }
                _popParams( $saved ) if $saved;
            } else {
                $newTopic = Foswiki::Sandbox::untaintUnchecked( $newname );
                ($newWeb, $newTopic) = Foswiki::Func::normalizeWebTopicName( $forkWeb, $newTopic );
                unless (
                        Foswiki::Func::isValidTopicName( $newTopic, 1 ) &&
                        Foswiki::Func::isValidWebName( $newWeb ) ) {
                    $erroneous .= '%MAKETEXT{"Invalid destination to fork to: [_1]" args="'."'$newWeb.$newTopic'\"}%\n\n";
                    next;
                }

                $newAction = $defaultAction;
                unless ( $newAction ) {
                    $erroneous .= '%MAKETEXT{"No transition with =FORK= attribute to fork"}% '."$newTopic\n\n";
                    next;
                }
            }

            push( @webs, $newWeb );
            push( @topics, $newTopic );
            push( @actions, $newAction );
            push( @params, $withParams );
        }

        # Now copy the topics and do the transitions.
        unless ($erroneous) {
            while (scalar @topics) {
                my $newTopic = shift @topics;
                my $newAction = shift @actions;
                my $newWeb = shift @webs;
                my $withParams = shift @params;

                my $saved;
                $saved = _pushParams( $withParams ) if $withParams;

                if (Foswiki::Func::topicExists($newWeb, $newTopic)) {
                    $directToWeb = $newWeb;
                    $directToTopic = $newTopic;
                    next;
                }

                my $newControlledTopic = _createForkedCopy($session, $ttmeta, $newWeb, $newTopic);
                unless ( $newControlledTopic ) {
                    $erroneous .= '%MAKETEXT{"Could not initialize workflow for"}% '."$newWeb.$newTopic\n\n";
                    next; # XXX this leaves the created topic behind
                }

                $directToWeb = $newWeb;
                $directToTopic = $newControlledTopic->{topic}; # might have changed due to AUTOINC

                Foswiki::Func::pushTopicContext($newWeb, $newControlledTopic->{topic}); # have %TOPIC% point to correct location
                my $mail = $newControlledTopic->changeState($newAction);
                Foswiki::Func::popTopicContext();
                local $isStateChange = 1;
                $newControlledTopic->save(1);
                local $isStateChange = 0;
                push(@$mails, $mail);

                _popParams( $saved ) if $saved;

                # Topic successfully forked
            }

        }
    }

    if ($erroneous) {
        Foswiki::Func::writeWarning($erroneous);
        my $message = Foswiki::Func::expandCommonVariables($erroneous);
        throw Foswiki::OopsException(
            'workflowfork',
            def   => 'topic_access',
            params => $message
        );
        return "Error";
    }

    foreach my $mail ( @$mails ) {
        sendKVPMail($mail);
    }

    #redirect to last successfully forked topic
    return $response->redirect(Foswiki::Func::getViewUrl($directToWeb, $directToTopic));
}

sub _createForkedCopy {
    my ($session, $ttmeta, $newWeb, $newTopic) = @_;

    if($newTopic =~ m#AUTOINC\d+#) {
        require Foswiki::UI::Save;
        $newTopic = Foswiki::UI::Save::expandAUTOINC( $session, $newWeb, $newTopic );
    }

    my $now = Foswiki::Func::formatTime( time(), undef, 'servertime' );
    my $who = Foswiki::Func::getWikiUserName();

    my $forkWeb = $ttmeta->web();
    my $forkTopic = $ttmeta->topic();

    #Alex: Topic mit allen Dateien kopieren
    if ( $session->{store}->can('copyTopic') ) { # PlainFileStore
        my $meta = new Foswiki::Meta($session, $newWeb, $newTopic);
        $session->{store}->copyTopic($ttmeta, $meta);
    } elsif( $session->{store}->can('getHandler') ) { # Rcs
        my $handler = $session->{store}->getHandler( $forkWeb, $forkTopic );
        $handler->copyTopic($session->{store}, $newWeb, $newTopic);
    } else {
        die 'Can not fork topic with current store implementation.';
    }

    my $meta = new Foswiki::Meta($session, $newWeb, $newTopic);
    foreach my $k ( keys %$ttmeta ) {
        # Note that we don't carry over the history from the forked topic
        next if ( $k =~ /^_/ || $k eq 'WORKFLOWHISTORY' );
        my @data;
        foreach my $item ( @{ $ttmeta->{$k} } ) {
            my %datum = %$item;
            push( @data, \%datum );
        }
        $meta->putAll( $k, @data );
    }

    my $forkhistory = {
        value => "<br />Forked from [[$forkWeb.$forkTopic]] by $who at $now",
    };
    $meta->put( "WORKFLOWHISTORY", $forkhistory );

    my $origin = _getOrigin($newTopic);
    if($newTopic ne $origin && Foswiki::Func::topicExists($newWeb, $origin)) {
        # index workflow_hasdiscussion_b change
        _requestSolrUpdate("$newWeb." . $origin);
    }

    return _initTOPIC( $newWeb, $newTopic, undef, $meta, FORCENEW );
}

# Notify the SolrWorker, that we want a topic indexed.
sub _requestSolrUpdate {
    my ( $topic ) = @_;

    return unless $Foswiki::cfg{Plugins}{TaskDaemonPlugin}{Enabled} && $Foswiki::cfg{Plugins}{SolrPlugin}{Enabled};

    use Foswiki::Plugins::TaskDaemonPlugin;
    Foswiki::Plugins::TaskDaemonPlugin::send($topic, 'update_topic', 'SolrPlugin');
}

sub isStateChange() {
    return $isStateChange;
}

# XXX requires changes in lib/Foswiki/Meta.pm
# Will check if the workflow permits the user to move topics and rename attachments.
#
# When the context 'IgnoreKVPPermission' is true, this handler will
# be ignored.
sub beforeRenameHandler {
    my( $oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment ) = @_;

    my $context = Foswiki::Func::getContext();
    return if $context->{'IgnoreKVPPermission'};

    return if $isStateChange;

    # Handle attachment renames.
    # Only allow it if user has write-permissions to the topic
    if( $newAttachment ) {
        # check old topic
        my $controlledTopic = _initTOPIC( $oldWeb, $oldTopic );

        if( $controlledTopic && not $controlledTopic->canEdit() ) {
            throw Foswiki::OopsException( # XXX Wrong template
                'workflowerr',
                def   => 'topic_access',
                web   => $oldWeb,
                topic => $oldTopic,
                params => "You may not modify $oldWeb.$oldTopic." # XXX maketext
            );
        }

        # check new topic
        return if( $oldWeb eq $newWeb && $oldTopic eq $newTopic );
        my $newControlledTopic = _initTOPIC( $newWeb, $newTopic );
        if( $newControlledTopic && not $newControlledTopic->canEdit() ) {
            throw Foswiki::OopsException( # XXX Wrong template
                'workflowerr',
                def   => 'topic_access',
                web   => $oldWeb,
                topic => $oldTopic,
                params => "You may not modify $newWeb.$newTopic." # XXX maketext
            );
        }
        return;
    }

    # Do not handle webs (attachments have already been handled)
    return unless $newTopic;

    # Not an attachment, nor a web, must be a topic.
    my $controlledTopic = _initTOPIC( $oldWeb, $oldTopic );
    if( $controlledTopic && !$controlledTopic->canMove() ){
        die("You may not move $oldWeb.$oldTopic.");
        throw Foswiki::OopsException( # not supported by bin/rename
            'workflowerr',
            def   => 'topic_access',
            web   => $oldWeb,
            topic => $oldTopic,
            params => "You may not move $oldWeb.$oldTopic." # XXX maketext
        );
    }
    my ($meta, undef) = Foswiki::Func::readTopic($oldWeb, $oldTopic);
    my $newControlledTopic = _initTOPIC( $newWeb, $newTopic, undef, $meta, 1 );
    if( $newControlledTopic && !$newControlledTopic->canEdit() ){
        die("You may not move to $newWeb.$newTopic.");
        throw Foswiki::OopsException( # not supported by bin/rename
            'workflowerr',
            def   => 'topic_access',
            web   => $oldWeb,
            topic => $oldTopic,
            params => "You may not move to $newWeb.$newTopic." # XXX maketext
        );
    }
}

# Used to trap an edit and check that it is permitted by the workflow
sub beforeEditHandler {
    my ( $text, $topic, $web, $meta ) = @_;

    # FlexFormPlugin dispatches the handler again, usually on the template topic.
    # As a workaround, only perform this check in the first handler dispatched in
    # an edit session. (MODAC #5049)
    return if Foswiki::Func::getContext()->{kvp_beforeedit_done};
    Foswiki::Func::getContext()->{kvp_beforeedit_done} = 1;

    my $query = Foswiki::Func::getCgiQuery();
    if($meta && $query->param('templatetopic')) {
        _onTemplateExpansion( $web, $topic, $meta, 1 );

        # For better compatibility with FlexFormPlugin's RENDERFORDISPLAY, copy all field values into the query object
        my $request = Foswiki::Func::getCgiQuery();
        for my $field ($meta->find('FIELD')) {
            next if defined $request->param($field->{name});
            $request->param($field->{name}, $field->{value});
        }
    }

    my $controlledTopic = _initTOPIC( $web, $topic, undef, undef, undef, NOCACHE );

    return unless $controlledTopic; # not controlled, so check not required

    #Alex: Checken ob Edit erlaubt ist
    unless ( $controlledTopic->canEdit() ) {
        my $message = Foswiki::Func::expandCommonVariables('%MAKETEXT{"You are not permitted to edit this topic. You have been denied access by workflow restrictions."}%');
        throw Foswiki::OopsException(
            'accessdenied',
            status => 403,
            def    => 'topic_access',
            web    => $_[2],
            topic  => $_[1],
            params => [
                'Edit topic',
                $message
            ]
        );
    }
}

# This beforeUploadHandler will attempt to cancel an upload if the user is
# denyed editing by the workflow.
# If the topic does not yet exist, it will tell the afterUploadHandler to mark this topic as a "stub".
sub beforeUploadHandler {
    my ( $attrs, $meta ) = @_;

    my $web = $meta->web();
    my $topic = $meta->topic();

    # XXX unfortunately we can not handle KVPSTATECHANGE, because Meta.pm will do a loadVersion afterwards.

    my $controlledTopic = _initTOPIC( $web, $topic, undef, undef, undef, NOCACHE  );
    return unless $controlledTopic;

    unless ( $controlledTopic->canEdit() ) {
        my $message = Foswiki::Func::expandCommonVariables('%MAKETEXT{"You are not permitted to upload to this topic. You have been denied access by workflow restrictions."}%');
        throw Foswiki::OopsException(
            'workflowerr',
            def   => 'topic_access',
            web   => $web,
            topic => $topic,
            params => $message
         );
    }
    unless(Foswiki::Func::topicExists($web, $topic)) {
        # This topic has probably been created just to attach a file.
        # Mark it as a stub.
        $markAsStub = 1;
    }
}

# Store "WorkflowStub" preference, see beforeUploadHandler
sub afterUploadHandler {
    my ($attrs, $meta) = @_;

    if($markAsStub) {
        $markAsStub = 0;
        $meta->putKeyed('PREFERENCE', { name => 'WorkflowStub', title=>'WorkflowStub', type=>'Set', value=>'1' });
        $meta->saveAs();
    }
}

sub _onTemplateExpansion {
    my ( $web, $topic, $meta, $early ) = @_;

    my $pre = (($early)?'Early':'');

    # get those values now, or they might be removed
    my $removeMeta = $meta->get( 'PREFERENCE', $pre.'RemoveMeta' );
    my $removePref = $meta->get( 'PREFERENCE', $pre.'RemovePref' );
    my $setForm = $meta->get( 'PREFERENCE', $pre.'SetForm' );
    my $setField = $meta->get( 'PREFERENCE', $pre.'SetField' );
    my $setMeta = $meta->get( 'PREFERENCE', $pre.'SetMeta' );
    my $setPref = $meta->get( 'PREFERENCE', $pre.'SetPref' );

    unless($early) {
        $meta->remove('PREFERENCE', 'RemoveMeta');
        $meta->remove('PREFERENCE', 'RemovePref');
        $meta->remove('PREFERENCE', 'SetForm');
        $meta->remove('PREFERENCE', 'SetField');
        $meta->remove('PREFERENCE', 'SetMeta');
        $meta->remove('PREFERENCE', 'SetPref');
        $meta->remove('PREFERENCE', 'EarlyRemoveMeta');
        $meta->remove('PREFERENCE', 'EarlyRemovePref');
        $meta->remove('PREFERENCE', 'EarlySetForm');
        $meta->remove('PREFERENCE', 'EarlySetField');
        $meta->remove('PREFERENCE', 'EarlySetMeta');
        $meta->remove('PREFERENCE', 'EarlySetPref');
    }

    # First set stuff, as it might require values that are to be removed.
    # SetForm:
    if($setForm) {
        $setForm = Foswiki::Func::expandCommonVariables(
            $setForm->{value}, $topic, $web, $meta);
        $setForm =~ s#^\s*##g;
        $setForm =~ s#\s*$##g;
        $meta->remove('FORM');
        $meta->put('FORM', { name => $setForm } );
    }
    # SetField:
    if($setField) {
        $setField = Foswiki::Func::expandCommonVariables(
            $setField->{value}, $topic, $web, $meta
        );
        while($setField =~ m/"\s*([^"]+?)\s*=\s*([^"]*?)\s*"/g) {
          my $toSet = $1;
          my $value = $2;
          $value =~ s#\$quot#"#g;
          $value =~ s#\$dollar#\$#g;
          $meta->putKeyed('FIELD', { name => $toSet, title => $toSet, type => 'Set', value => $value } );
        }
    }
    # RemoveMeta:
    if($removeMeta) {
        my $removeList = Foswiki::Func::expandCommonVariables(
            $removeMeta->{value}, $topic, $web, $meta
        );
        my @toRemove = split(",", $removeList);
        foreach my $item (@toRemove) {
            $item =~ s#^\s*##;
            $item =~ s#\s*$##;
            $meta->remove($item);
        }
    }
    # SetMeta:
    if($setMeta) {
        $setMeta = Foswiki::Func::expandCommonVariables(
            $setMeta->{value}, $topic, $web, $meta
        );
        while($setMeta =~ m/"\s*([^"]+?)\s*=\s*([^"]*?)\s*"/g) {
            my $toSet = $1;
            my $csv = $2;
            my $hash = ();
            foreach my $value (split('\s*,\s*', $csv)) {
                $value =~ s#\$comma#,#g;
                $value =~ s#\$quot#"#g;
                $value =~ s#\$dollar#\$#g;
                while($value =~ m#(.*?)=(.*)#g) {
                    $hash->{$1} = $2;
                }
            }
            $meta->putKeyed(
                $toSet, $hash
            );
        }
    }
    # RemovePref:
    if($removePref) {
        my $removeList = Foswiki::Func::expandCommonVariables(
            $removePref->{value}, $topic, $web, $meta
        );
        my @toRemove = split(",", $removeList);
        foreach my $item (@toRemove) {
            $item =~ s#^\s*##;
            $item =~ s#\s*$##;
            $meta->remove('PREFERENCE', $item);
        }
    }
    # SetPref:
    if($setPref) {
        $setPref = Foswiki::Func::expandCommonVariables(
            $setPref->{value}, $topic, $web, $meta
        );
        while($setPref =~ m/"\s*([^"]+?)\s*=\s*([^"]*?)\s*"/g) {
            my $toSet = $1;
            my $value = $2;
            $value =~ s#\$quot#"#g;
            $value =~ s#\$dollar#\$#g;
            $meta->putKeyed(
                'PREFERENCE',
                { name => $toSet, title => $toSet, type => 'Set', value => $value }
            );
        }
    }
}

# Copies stuff from a templatetopic to the topicObject
# Mostly copied from Foswiki::UI::Save, which doesn't do this when the topic already exists.
sub _XXXCopyTemplateStuffFromCore {
    my ($query, $topicObject) = @_;
    my $templateWeb = $topicObject->web;
    my $templateTopic = $query->param('templatetopic');
    my $ttom;
    my $text;
    my $session = $Foswiki::Plugins::SESSION;
    my @attachments = ();

    # Chunk copied from Foswiki::UI::Save::buildNewTopic
    # changes:
    #    * not changing text of topicObject
    #    * copy metadata after copying attachments and check their existance

    my ( $invalidTemplateWeb, $invalidTemplateTopic ) =
      $session->normalizeWebTopicName( $templateWeb, $templateTopic );

    $templateWeb = Foswiki::Sandbox::untaint( $invalidTemplateWeb,
        \&Foswiki::Sandbox::validateWebName );
    $templateTopic = Foswiki::Sandbox::untaint( $invalidTemplateTopic,
        \&Foswiki::Sandbox::validateTopicName );

    unless ( $templateWeb && $templateTopic ) {
        throw Foswiki::OopsException(
            'attention',
            def => 'invalid_topic_parameter',
            params =>
              [ scalar( $query->param('templatetopic') ), 'templatetopic' ]
        );
    }
    unless ( $session->topicExists( $templateWeb, $templateTopic ) ) {
        throw Foswiki::OopsException(
            'attention',
            def   => 'no_such_topic_template',
            web   => $templateWeb,
            topic => $templateTopic
        );
    }

    # Initialise new topic from template topic
    $ttom = Foswiki::Meta->load( $session, $templateWeb, $templateTopic );
    Foswiki::UI::checkAccess( $session, 'VIEW', $ttom );

    $text = $ttom->text();
    #$text = '' if $query->param('newtopic');    # created by edit
    #$topicObject->text($text);

    foreach my $k ( keys %$ttom ) {

        # change: Will copy metadata later, because copyAttachment might leak metadata if the save gets abortet
        # change: check if attachment exists in store, because we do want to avoid an exception

        # attachments to be copied later
        if ( $k eq 'FILEATTACHMENT' ) {
            foreach my $a ( @{ $ttom->{$k} } ) {
                next unless $ttom->hasAttachment($a->{name}); # change: make sure it exists
                push(
                    @attachments,
                    {
                        name => $a->{name},
                        tom  => $ttom,
                    }
                );
            }
        }
    }

    # Chunk copied from Foswiki::UI::Save::save
    # change: changed $attachments to @attachments

    if (scalar @attachments) {
        foreach $a ( @attachments ) {
            try {
                $a->{tom}->copyAttachment( $a->{name}, $topicObject );
            }
            catch Foswiki::OopsException with {
                shift->throw();    # propagate
            }
            catch Error with {
                $session->logger->log( 'error', shift->{-text} );
                throw Foswiki::OopsException(
                    'attention',
                    def    => 'save_error',
                    web    => $topicObject->web,
                    topic  => $topicObject->topic,
                    params => [
                        $session->i18n->maketext(
                            'Operation [_1] failed with an internal error',
                            'copyAttachment'
                        )
                    ],
                );
            };
        }
    }

    # change: do the loop again and really do copy the metadata
    foreach my $k ( keys %$ttom ) {

        # Skip internal fields and TOPICINFO, TOPICMOVED
        unless ( $k =~ m/^(_|TOPIC|FILEATTACHMENT)/ ) {
            # copyFrom overwrites old values
            my @oldMeta = $topicObject->find( $k );
            if( scalar @oldMeta ) {
                my @newMeta = $ttom->find( $k );
                $topicObject->putAll( $k, @newMeta, @oldMeta ); # XXX Why do I have to re-put the old values? A simple put will clear them...
            } else {
                $topicObject->copyFrom( $ttom, $k );
            }
        }
    }

}

# The beforeSaveHandler inspects the request parameters to see if the
# right params are present to trigger a state change. The legality of
# the state change is *not* checked - it's assumed that the change is
# coming as the result of an edit invoked by a state transition.
#
# When the context 'IgnoreKVPPermission' is true, this handler will
# be ignored.
sub beforeSaveHandler {
    my ( $text, $topic, $web, $meta ) = @_;

    my $context = Foswiki::Func::getContext();
    return if $context->{'IgnoreKVPPermission'};

    my $query = Foswiki::Func::getCgiQuery();
    return if($query->url() =~ m#/bin/jsonrpc$#); # XXX always pass MetaCommentPlugin
    return if($query->url() =~ m#/bin/rename$#); # XXX beforeSaveHandler will be called AFTER moving it, so here its to late
                                                 # This would also interrupt correcting links when renaming a topic and the user not having "allow change" rights in the linking topic

    # Do the RemoveMeta, RemovePref, SetForm, SetField, SetPref if save came from a template
    if($query->param('templatetopic')) {
        if(Foswiki::Func::topicExists($web, $topic)) {
            # Oh no, the topic already exists and the core will no longer copy stuff from the template!
            # We will have to do it instead...
            _XXXCopyTemplateStuffFromCore($query, $meta);
        }

        # We don't ever want to copy over the workflow state from a template
        $meta->remove('WORKFLOW');
        $meta->remove('WORKFLOWHISTORY');
        $meta->remove('WRKFLWCONTRIBUTORS');

        _onTemplateExpansion( $web, $topic, $meta, 0 );
    }

    # $isStateChange is true if state has just been changed in this session.
    # In this case we don't need the access check.
    return if ($isStateChange);

    # not a state-change, remove old state-change comment if present
    if($meta->get( 'KVPSTATECHANGE' )) {
        $meta->remove( 'KVPSTATECHANGE' );
        # XXX a new revision should be forced here
        # Possibility:
        # sub beforeSaveHandler {
        #   ...
        #   if($meta->get( 'KVPSTATECHANGE' )) {
        #     ...
        #     our $ReplaceIfEditedAgainWithin = $Foswiki::cfg{ReplaceIfEditedAgainWithin};
        #     $Foswiki::cfg{ReplaceIfEditedAgainWithin} = 0;
        #   }
        #   ...
        # }
        # sub initPlugin {
        #   ...
        #   our $ReplaceIfEditedAgainWithin;
        #   if(defined $ReplaceIfEditedAgainWithin) {
        #     $Foswiki::cfg{ReplaceIfEditedAgainWithin} = $ReplaceIfEditedAgainWithin;
        #     undef $ReplaceIfEditedAgainWithin;
        #   }
        # }
    }

    my $oldControlledTopic = _initTOPIC( $web, $topic, undef, undef, NOCACHE );
    my $controlledTopic = _initTOPIC( $web, $topic, undef, $meta, FORCENEW );

    if ( $oldControlledTopic && !$oldControlledTopic->canEdit() ) {
        # Not a state change, make sure the AllowEdit in the state table
        # permits this action
        my $message = Foswiki::Func::expandCommonVariables('%MAKETEXT{"You are not permitted to save this topic. You have been denied access by workflow restrictions."}%', $topic, $web, $meta);
        throw Foswiki::OopsException(
            'workflowerr',
            def   => 'topic_access',
            web   => $_[2],
            topic => $_[1],
            params => $message
        );
    } else {
        return unless $controlledTopic;

        my $newMeta = new Foswiki::Meta($Foswiki::Plugins::SESSION, $web, $topic, $text);
        my @newStateName = $newMeta->find('WORKFLOW');
        if(scalar @newStateName > 1) { # If 0 this is a new topic, or not controlled, or created without workflow
            my $message = Foswiki::Func::expandCommonVariables('%MAKETEXT{"Must find exactly one workflow in the topic, but found [_1]." args="'.scalar(@newStateName).'"}%', $topic, $web, $meta);
            throw Foswiki::OopsException(
                    'workflowerr',
                     def   => 'topic_access',
                     web   => $_[2],
                     topic => $_[1],
                     params => $message
            );
        }
        # TODO Check if metacommentstuff changed unless workflow does so

        if( Foswiki::Func::topicExists( $web, $topic )
                && not $meta->getPreference('WorkflowStub') ) {
            # topic already exists, check if Workflowstuff didn't change
            # but do not touch uncontrolled topics
            if(scalar @newStateName == 0) {
                return;
            }

            my $oldMeta = $oldControlledTopic->{meta};
            my $oldState = $oldMeta->get( 'WORKFLOW' );
            unless($newStateName[0]->{name} eq $oldState->{name}) {
                my $message = Foswiki::Func::expandCommonVariables("%MAKETEXT{\"The workflow state did not match the current state.\n\nA common reason is an old article in the browser cache. Please edit the article again via the wiki frontend.\n\n(stored state: [_1], new state: [_2])\" args=\"".($oldState->{name} || 'none').','.($newStateName[0]->{name} || 'none').'"}%', $topic, $web, $meta);
                throw Foswiki::OopsException(
                    'workflowerr',
                     def   => 'topic_access',
                     web   => $_[2],
                     topic => $_[1],
                     params => $message
                );
            }
# XXX Kommentare sind nicht schreibgeschtzt
#remove klappt nicht, weils im text steht            $meta->remove('COMMENT');
#            foreach my $comment ($oldMeta->find( 'COMMENT' )) {
#                $meta->putKeyed('COMMENT', $comment);
#            }

            # check 'Allow Field ...'
            my @deniedFields = ();
            foreach my $field ( $controlledTopic->getDeniedFields() ) {
                my $oldHash = $oldMeta->get('FIELD', $field);
                my $oldValue = ($oldHash)?$oldHash->{value}:'';
                my $newHash = $meta->get('FIELD', $field);
                my $newValue = ($newHash)?$newHash->{value}:'';
                unless ( $oldValue eq $newValue ) {
                   push(@deniedFields, Foswiki::Func::expandCommonVariables('%MAKETEXT{"You are not allowed to change formfield [_1] from \"[_2]\" to \"[_3]\""'." arg1=\"$field\" arg2=\"$oldValue\" arg3=\"$newValue\"}%"));
               }
            }
            if(@deniedFields) {
                throw Foswiki::OopsException(
                        'workflowerr',
                        def   => 'topic_access',
                        web   => $_[2],
                        topic => $_[1],
                        params => join("\n\n", @deniedFields),
                );
            }

            # perform AUTO actions
            my ($autoAction, undef) = @{$controlledTopic->getActionWithAttribute('AUTO')};
            if($autoAction) {
                my $mail = $controlledTopic->changeState($autoAction);
		sendKVPMail($mail);
            }
        } else {
            # This topic is now no longer a stub.
            $controlledTopic->{meta}->remove('PREFERENCE', 'WorkflowStub');
            # XXX This check does not work properly
            # Make sure that newly created topics can't cheat with their state
            if(scalar @newStateName > 1) { # If 0 this is a new topic, or not controlled, if it's a copy it may be 1.
                my $message = Foswiki::Func::expandCommonVariables('%MAKETEXT{"Found an invalid workflow (there must be none in a newly created topic)."}%');
                throw Foswiki::OopsException(
                        'workflowerr',
                        def   => 'topic_access',
                        web   => $_[2],
                        topic => $_[1],
                        params => $message
                );
            }
            # Assure that newly created topics have a state
#always overwrite?            unless ($mstate && $mstate->{ state }) {
                my ($newAction, undef) = @{$controlledTopic->getActionWithAttribute('NEW')};
                if($newAction) {
                    my $mail = $controlledTopic->changeState($newAction);
                    sendKVPMail($mail);
                } elsif ( not ( Foswiki::Func::isAnAdmin() || $Foswiki::cfg{Plugins}{KVPPlugin}{NoNewRequired} ) ) {
                    my $message = Foswiki::Func::expandCommonVariables('%MAKETEXT{"You may not create this topic under this workflow."}%');
                    throw Foswiki::OopsException(
                        'workflowerr',
                        def => 'topic_creation',
                        web => $web,
                        topic => $topic,
                        params => $message
                    );
                }

                # check 'Allow Field ...'
                my @deniedFields = ();
                foreach my $field ( $controlledTopic->getDeniedFields() ) {
                    my $newHash = $meta->get('FIELD', $field);
                    if ( $newHash && $newHash->{value} ) {
                        push(@deniedFields, Foswiki::Func::expandCommonVariables('%MAKETEXT{"You are not allowed to fill formfield [_1]"." args="'."$field\"}%"));
                    }
                }
                if(@deniedFields) {
                    throw Foswiki::OopsException(
                            'workflowerr',
                            def   => 'topic_access',
                            web   => $_[2],
                            topic => $_[1],
                            params => join("\n\n", @deniedFields),
                    );
                }

        }
    }

    $controlledTopic->addContributors(Foswiki::Func::getWikiUserName());
}

sub _getIndexHash {
    my ($web, $topic, $meta) = @_;

    my %indexFields = ();

    $indexFields{ workflow_origin_s } = _getOrigin("$web.$topic");

    # only index controlled topics, or old metadata will end up in index.
    my $controlledTopic = _initTOPIC( $web, $topic, undef, $meta, NOCACHE );

    if( $controlledTopic ) {
        $indexFields{ workflow_controlled_b } = 1;
    } else {
        $indexFields{ workflow_controlled_b } = 0;
        my $fields = $Foswiki::cfg{Extensions}{KVPPlugin}{uncontrolledRow};
        if ( $fields ) {
            Foswiki::Func::pushTopicContext($web, $topic);
            foreach my $field (keys %$fields) {
                next if $field =~ m#^(?:approved$|allow|state$)#; # skip those already indexed
                $indexFields{ "workflowstate_${field}_s" } = Foswiki::Func::expandCommonVariables($fields->{$field});
            }
            $indexFields{ process_state_s } = $fields->{state} if $fields->{state};
            $indexFields{ workflow_isapproved_b } = ($fields->{approved})?1:0;
            Foswiki::Func::popTopicContext();
        }
        return %indexFields;
    }

    $indexFields{ workflow_controlledby_s } = $controlledTopic->getWorkflowName();

    # might result in default-state
    my $state = $controlledTopic->getState();
    $indexFields{ process_state_s } = $state if $state;

    $indexFields{ workflow_isapproved_b } = ($controlledTopic->getRow( 'approved' ))?1:0;

    # Modac : Mega Easy Implementation
    my $workflow = $meta->get('WORKFLOW');
    return %indexFields unless ( $workflow ); # might happen when topics are created outside workflow and then move into a workflowed web

    # provide ALL the fields
    for my $key (keys %$workflow) {
        my $lckey = lc($key);
        $indexFields{ "workflowmeta_${lckey}_s" } = $workflow->{$key};
        if($workflow->{"${key}_DT"}) {
            $indexFields{ "workflowmeta_${lckey}_dt" } = Foswiki::Time::formatTime($workflow->{"${key}_DT"}, '$year-$mo-$dayT$hours:$mins:$secondsZ', 'gmtime');
        } else {
            if($lckey =~ m#^lasttime_# && $workflow->{$key} =~ m#(\d{1,2})\.(\d{1,2})\.(\d{4})#) {
                $indexFields{ "workflowmeta_${lckey}_dt" } = "$3-$2-${1}T00:00:00Z";
            }
        }
    }

    # alias to workflowmeta_..._currentstate_..
    for my $key (keys %$workflow) {
        next unless $key =~ m#$state$#;
        my $keycopy = $key;
        $keycopy =~ s#$state$#currentstate#;
        my $lckey = lc($keycopy);
        $indexFields{ "workflowmeta_${lckey}_s" } = $workflow->{$key};
        if($workflow->{"${key}_DT"}) {
            $indexFields{ "workflowmeta_${lckey}_dt" } = Foswiki::Time::formatTime($workflow->{"${key}_DT"}, '$year-$mo-$dayT$hours:$mins:$secondsZ', 'gmtime');
        } else {
            if($lckey =~ m#^lasttime_# && $workflow->{$key} =~ m#(\d{1,2})\.(\d{1,2})\.(\d{4})#) {
                $indexFields{ "workflowmeta_${lckey}_dt" } = "$3-$2-${1}T00:00:00Z";
            }
        }
    }

    # provide all state info
    { # scope
        my $fields = $controlledTopic->getFields();
        if ( $fields ) {
            foreach my $field (keys %$fields) {
                next if $field =~ m#^(?:approved$|allow|state$)#; # skip those already indexed
                if($field =~ m#^displayname(\w*)$#) {
                    $indexFields{ "workflowstate_${field}_s" } = $controlledTopic->getWorkflowMeta('displayname', $1, 1);
                    $indexFields{ "previousstate_${field}_s" } = $controlledTopic->{workflow}->getDisplayname($workflow->{previousState}, $1, 1) if $workflow->{previousState};
                } else {
                    $indexFields{ "workflowstate_${field}_s" } = $controlledTopic->expandMacros($controlledTopic->getRow($field, 1));
                }
            }
        }
    }

    # fallback for old topics
    my $statetype = lc($controlledTopic->getRow('statetype'));
    if(!exists $indexFields{"workflowmeta_lasttimestatetype_${statetype}_dt"} && exists $indexFields{"workflowmeta_lasttime_${statetype}_dt"}) {
        $indexFields{"workflowmeta_lasttimestatetype_${statetype}_s"} = $indexFields{"workflowmeta_lasttime_${statetype}_s"};
        $indexFields{"workflowmeta_lasttimestatetype_${statetype}_dt"} = $indexFields{"workflowmeta_lasttime_${statetype}_dt"};
        $indexFields{"workflowmeta_lastprocessorstatetype_${statetype}_s"} = $indexFields{"workflowmeta_lastprocessor_${statetype}_s"};
    }
    if(exists $indexFields{"workflowmeta_lasttimestatetype_${statetype}_dt"}) {
        $indexFields{"workflowmeta_lasttimecurrentstatetype_s"} = $indexFields{"workflowmeta_lasttimestatetype_${statetype}_s"};
        $indexFields{"workflowmeta_lasttimecurrentstatetype_dt"} = $indexFields{"workflowmeta_lasttimestatetype_${statetype}_dt"};
        $indexFields{"workflowmeta_lastprocessorcurrentstatetype_s"} = $indexFields{"workflowmeta_lastprocessorstatetype_${statetype}_s"};
    }

    # Contributors
    my @cHashes = $controlledTopic->{meta}->find('WRKFLWCONTRIBUTORS');
    foreach my $contis (@cHashes) {
        my $field = 'workflow_contributors_'.lc($contis->{name}).'_lst';
        foreach my $person (split(',', $contis->{value})) {
            $indexFields{ $field } = $person;
        }
    }

    my $suffix = _WORKFLOWSUFFIX();
    $indexFields{ workflow_hasdiscussion_b } = Foswiki::Func::topicExists($web, "$topic$suffix")?1:0;

    # mild sanity-test if state exists (eg. Workflow-table changed and state got renamed)
    if($controlledTopic && not $controlledTopic->getRow('state') eq $state) {
        Foswiki::Func::writeWarning("Workflow error in $web.$topic");
        $indexFields{ workflow_tasked_lst } = 'KvpError';
    }

    # index tasks
    if($workflow->{TASK}) {
        my $taskedPeople = $controlledTopic->getTaskedPeople();
        unless ($taskedPeople && scalar @$taskedPeople) {
            $indexFields{ workflow_tasked_lst } = 'KvpTaskedNobody';
        } else {
            foreach my $user ( @$taskedPeople ) {
                $indexFields{ workflow_tasked_lst } = $user;
                if( $Foswiki::cfg{Extensions}{KVPPlugin}{MonitorTasked}
                        && not Foswiki::Func::wikiToUserName( $user ) ) {
                    $indexFields{ workflow_tasked_lst } = 'KvpUnknownUser';
                }
            }
        }
    }

    _addDisplayValuesToIndexHash(\%indexFields);

    return %indexFields;
}

sub _addDisplayValuesToIndexHash {
    my $indexFields = shift;

    foreach my $indexField (keys(%$indexFields)) {
        if($indexField =~ m#^(workflowmeta_lastprocessor.*)_s$#) {
            my $displayValueField = $1.'_dv_s';
            my $value = $indexFields->{$indexField};
            $indexFields->{$displayValueField} = Foswiki::Func::expandCommonVariables("%RENDERUSER{\"$value\"}%");
        }
    }
}

sub indexTopicHandler {
    my ($indexer, $doc, $web, $topic, $meta, $text) = @_;

    our $indexCacheWebTopic = $web.$topic;
    our %indexFields = _getIndexHash( $web, $topic, $meta );

    $doc->add_fields( %indexFields );
}

sub indexAttachmentHandler {
    my ($indexer, $doc, $web, $topic, $attachment) = @_;

    our $indexCacheWebTopic;
    our %indexFields;

    unless ( $indexCacheWebTopic && $indexCacheWebTopic eq $web.$topic ) {
        Foswiki::Func::writeWarning("Cache missed for attachment: $web.$topic");
        my ($meta, undef) = Foswiki::Func::readTopic( $web, $topic );
        $indexCacheWebTopic = $web.$topic;
        %indexFields = _getIndexHash( $web, $topic, $meta );
    }

    $doc->add_fields( %indexFields );
}

# Will send mails generated by transitionTopic
# Parameters:
#    * $mail: hash created by transitionTopic; must have these keys:
#        * template: the template to use to generate the mail
#        * options: options-hash for MailTemplatesContrib
#        * settings: settings-hash for MailTemplatesContrib
#        * extra: debug-info-hash for 'MonitorMails'
sub sendKVPMail {
    my ($mail) = @_;

    return unless $mail;

    Foswiki::Contrib::MailTemplatesContrib::sendMail($mail->{template}, $mail->{options}, $mail->{settings}, 1);

    Foswiki::Func::writeWarning("Topic: '$mail->{options}{webtopic}' Transition: '$mail->{extra}{action}' Notify column: '$mail->{extra}{ncolumn}'") if $Foswiki::cfg{Extensions}{KVPPlugin}{MonitorMails};
}

sub maintenanceHandler {
    Foswiki::Plugins::MaintenancePlugin::registerCheck("KVPPlugin:pluginorder", {
        name => "KVPPlugin in PluginsOrder",
        description => "KVPPlugin should be in {PluginsOrder} for EarlySetField.",
        check => sub {
            unless($Foswiki::cfg{PluginsOrder} =~ m#\bKVPPlugin\b#) {
                return {
                    result => 1,
                    priority => $Foswiki::Plugins::MaintenancePlugin::WARN,
                    solution => "Add KVPPlugin to {PluginsOrder} in configure"
                }
            } else {
                return { result => 0 };
            }
        }
    });
    Foswiki::Plugins::MaintenancePlugin::registerCheck("KVPPlugin:pluginorder2", {
        name => "KVPPlugin after MoreFormfieldsPlugin in PluginsOrder",
        description => "KVPPlugin should be listed before MoreFormfieldsPlugin in {PluginsOrder}",
        check => sub {
            if($Foswiki::cfg{PluginsOrder} =~ m#\bMoreFormfieldsPlugin\b.*\bKVPPlugin\b#) {
                return {
                    result => 1,
                    priority => $Foswiki::Plugins::MaintenancePlugin::WARN,
                    solution => "Edit {PluginsOrder} in configure to list KVPPlugin before MoreFormfieldsPlugin"
                }
            } else {
                return { result => 0 };
            }
        }
    });
    Foswiki::Plugins::MaintenancePlugin::registerCheck("KVPPlugin:mailworkflowtransition.tmpl", {
        name => "Check if mailworkflowtransition.tmpl customized",
        description => "Customizing KVPPlugin's mailworkflowtransition.tmpl is no longer supported",
        check => sub {
            my @files = <"$Foswiki::cfg{TemplateDir}/mailworkflowtransition.*.tmpl">;
            if(scalar @files) {
                return {
                    result => 1,
                    priority => $Foswiki::Plugins::MaintenancePlugin::WARN,
                    solution => "Please change your customization (".join(', ', @files).") to conform with MailTemplatesContrib."
                }
            } else {
                return { result => 0 };
            }
        }
    });
    Foswiki::Plugins::MaintenancePlugin::registerCheck("KVPPlugin:AlternativeMetaCommentACLs", {
        name => "Check if alternative MetaCommentPlugin ACLs are used",
        description => "There is a better alternative ACL check for MetaComments",
        check => sub {
            my $isOk = 1;
            $isOk = 0 unless $Foswiki::cfg{Extensions}{KVPPlugin}{DoNotManageMetaCommentACLs};
            $isOk = 0 unless $Foswiki::cfg{MetaCommentPlugin}{AlternativeACLCheck};
            unless($isOk) {
                return {
                    result => 1,
                    priority => $Foswiki::Plugins::MaintenancePlugin::WARN,
                    solution => "It might be on purpose, but you have not configured the alternative ACL checks for MetaCommentPlugin."
                        . "<br/>Recommended settings are:"
                        . "<br/><em>\$Foswiki::cfg{Extensions}{KVPPlugin}{DoNotManageMetaCommentACLs}</em>=<em>enabled</em>"
                        . "<br/><em>\$Foswiki::cfg{Extensions}{KVPPlugin}{ScrubMetaCommentACLs}</em>=<em>enabled</em> (for legacy installations)"
                        . "<br/><em>\$Foswiki::cfg{MetaCommentPlugin}{AlternativeACLCheck}</em>=<em>%<nop>WORKFLOWALLOWS{\"allowcomment\" emptyIs=\"0\"}%</em>"
                }
            } else {
                return { result => 0 };
            }
        }
    });
    Foswiki::Plugins::MaintenancePlugin::registerCheck("KVPPlugin:StoreImplementation", {
        name => "KVPPlugin store compatibility",
        description => "Check if KVPPlugin supports current store implementation.",
        check => sub {
            my $session = $Foswiki::Plugins::SESSION;
            if (
                $session->{store}->can('copyTopic') # PlainFileStore
                || $session->{store}->can('getHandler') # Rcs
            ) {
                return { result => 0 };
            } else {
                return {
                    result => 1,
                    priority => $Foswiki::Plugins::MaintenancePlugin::ERROR,
                    solution => "Please re-install (Modac version of) PlainFileStoreContrib."
                }
            }
        }
    });
    Foswiki::Plugins::MaintenancePlugin::registerCheck("KVPPlugin:SkinOrder", {
        name => "Check if kvp skin is after metacomment skin.",
        description => "kvp should appear after (left of) metacomment in SKIN.",
        check => sub {

            # checks text of meta for wrong SKIN setting
            sub _check {
                my ( $meta, $failed ) = @_;

                foreach my $line ( split(m#\n#, $meta->text()) ) {
                    if ($line =~ m#$Foswiki::regex{setVarRegex}#) {
                        next unless $1 eq 'Set';
                        next unless $2 eq 'SKIN';
                        my $skin = $3;

                        if($skin =~ m#(.*,|^)\s*metacomment\s*,(.*)\bkvp\b(.*)#) {
                            my $pre = $1;
                            my $sep = $2;
                            my $tail = $3;

                            $failed->{$meta}->{reason} = $skin;
                            $failed->{$meta}->{suggestion} = "${pre}${sep}kvp,metacomment$tail";
                            $failed->{$meta}->{webtopic} = $meta->web().'.'.$meta->topic();
                        }
                    }
                }
            };

            my $failed = {};

            # SitePreferences
            (my $meta, undef) = Foswiki::Func::readTopic($Foswiki::cfg{UsersWebName}, 'SitePreferences');
            _check($meta, $failed);

            # WebPreferences
            foreach my $web ( Foswiki::Func::getListOfWebs ) {
                (my $meta, undef) = Foswiki::Func::readTopic($web, $Foswiki::cfg{WebPrefsTopicName});
                _check($meta, $failed);
            }

            if (scalar keys %$failed) {
                my $solution = 'Please put kvp after (left of) metacomment in SKIN variable:'
                    . '<table><thead><tr><th>Topic</th><th>Current</th><th>Recommended</th></tr><thead><tbody>';
                foreach my $failure ( sort keys %$failed ) {
                    my $webtopic = $failed->{$failure}->{webtopic};
                    $solution .= "<tr><td>[[$webtopic][$webtopic]]</td><td>".$failed->{$failure}->{reason}."</td><td>".$failed->{$failure}{suggestion}."</td></tr>";
                }
                $solution .= '</tbody></table>';

                return {
                    result => 1,
                    priority => $Foswiki::Plugins::MaintenancePlugin::ERROR,
                    solution => "$solution"
                }
            } else {
                return { result => 0 };
            }
        }
    });
    Foswiki::Plugins::MaintenancePlugin::registerCheck("KVPPlugin:MailTemplatesContrib:Version", {
        name => "KVPPlugin: MailTemplatesContrib version",
        description => "Check if MailTemplatesContrib needs to be updated.",
        check => sub {
            require Foswiki::Contrib::MailTemplatesContrib;
            my $release = $Foswiki::Contrib::MailTemplatesContrib::RELEASE;
            my @minRequired = (1, 0, 0);

            if ($release !~ m#(\d+)\.(\d+)(?:\.(\d+))?$#) {
                return {
                    result => 1,
                    priority => $Foswiki::Plugins::MaintenancePlugin::ERROR,
                    solution => "Could not parse your MailTemplatesContrib version. Probable cause: non-release branch. Please review version. Version: '$release'."
                };
            }
            my ($major, $minor, $build) = ($1, $2, $3);

            my $ok = { result => 0 };
            my $error = {
                result => 1,
                priority => $Foswiki::Plugins::MaintenancePlugin::ERROR,
                solution => "Your MailTemplatesContrib version ($release) does not meet the minimum requirements (".join('.', @minRequired)."), please update."
            };

            return $ok if( $major > $minRequired[0] );
            return $error if( $major < $minRequired[0] );
            return $ok if( $minor > $minRequired[1] );
            return $error if( $minor < $minRequired[1] );
            return $ok if ( not defined $build ) || $build >= $minRequired[2]; # $build not defined most likely means git repo.
            return $error;
        }
    });
}

1;
__END__

 Copyright (C) 2005 Thomas Hartkens <thomas@hartkens.de>
 Copyright (C) 2005 Thomas Weigert <thomas.weigert@motorola.com>
 Copyright (C) 2008-2010 Crawford Currie http://c-dot.co.uk
 Copyright (C) 2011-2014 Modell Aachen GmbH

 This program is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation; either version 2
 of the License, or (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details, published at
 http://www.gnu.org/copyleft/gpl.html
