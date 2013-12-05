# See bottom of file for license and copyright information

# TODO
# 1. Create initial values based on form when attaching a form for
#    the first time.
# 2. Allow appearance of button to be given in preference.

# =========================
package Foswiki::Plugins::KVPPlugin;

use strict;

use Error ':try';
use Assert;

use Foswiki::Func ();
use Foswiki::Plugins::KVPPlugin::Workflow ();
use Foswiki::Plugins::KVPPlugin::ControlledTopic ();
use Foswiki::OopsException ();
use Foswiki::Sandbox ();

use constant FORCENEW => 1;
use constant NOCACHE => 2;

our $VERSION = '2.0';
our $RELEASE = "2.0";
our $SHORTDESCRIPTION = 'Kontinuierliche Verbesserung im Wiki';
our $NO_PREFS_IN_TOPIC = 1;
our $pluginName       = 'KVPPlugin';
our %cache;
our $isStateChange;
# Although the origin is quick to calculate it is called often enough to be worth being cached
our $originCache;

sub initPlugin {
    my ( $topic, $web ) = @_;

    %cache = ();

    Foswiki::Func::registerRESTHandler(
        'changeState', \&_changeState,
        http_allow => 'POST' );
    Foswiki::Func::registerRESTHandler(
        'fork', \&_restFork,
        authenticate => 1, http_allow => 'GET' );
    Foswiki::Func::registerRESTHandler(
        'link', \&_restLink, 
        http_allow => 'GET' );

    Foswiki::Func::registerTagHandler(
        'WORKFLOWSTATE', \&_WORKFLOWSTATE );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWHISTORY', \&_WORKFLOWHISTORY );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWTRANSITION', \&_WORKFLOWTRANSITION );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWFORK', \&_WORKFLOWFORK );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWMETA', \&_WORKFLOWMETA );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWSUFFIX', \&_WORKFLOWSUFFIX );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWCONTRIBUTORS', \&_WORKFLOWCONTRIBUTORS );
    Foswiki::Func::registerTagHandler(
        'GETWORKFLOWROW', \&_GETWORKFLOWROW );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWEDITPERM', \&_WORKFLOWEDITPERM );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWORIGIN', \&_WORKFLOWORIGIN );

    # init the displayed topic to set according contexts for skin
    my $controlledTopic = _initTOPIC( $web, $topic );
    if ($controlledTopic) {
        my $context = Foswiki::Func::getContext();
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
            if (Foswiki::Func::topicExists($web, "$topic$suffix")) {
                $context->{'KVPHasDiscussion'} = 1;
            }
        } else {
            $context->{'KVPIsDiscussion'} = 1;
        }
    }
    our $originCache = _getOrigin( $topic );

    # Copy/Paste/Modify from MetaCommentPlugin
    # SMELL: this is not reliable as it depends on plugin order
    # if (Foswiki::Func::getContext()->{SolrPluginEnabled}) {
    if ($Foswiki::cfg{Plugins}{SolrPlugin}{Enabled}) {
      require Foswiki::Plugins::SolrPlugin;
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

    return $originCache unless $attributes->{_DEFAULT};
    return _getOrigin( $attributes->{_DEFAULT} || $topic );
}

sub _initTOPIC {
    my ( $web, $topic, $rev, $meta, $text, $forceNew ) = @_;

    # Skip system web for performance
    return undef if ($web eq "System");

    # Filter out topics inhibited in configure
    my $exceptions = $Foswiki::cfg{Extensions}{KVPPlugin}{except};
    return undef if $exceptions && $topic =~ /$exceptions/;

    $rev ||= 99999;    # latest

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

    my $workflowName;
    if ( $meta ) {
        # $meta->getPreference('WORKFLOW') does not necessarily do what I want,
        # eg. on a newly created topic it will return an empty string.
        # Unfortunately this won't cover a "   * Set WORKFLOW = ..."
        my $pref = $meta->get('PREFERENCE', 'WORKFLOW');
        $workflowName = $pref->{value} if $pref;
    }
    unless( defined $workflowName ) {
        Foswiki::Func::pushTopicContext( $web, $topic );
        $workflowName = Foswiki::Func::getPreferencesValue('WORKFLOW');
        Foswiki::Func::popTopicContext();
    }

    if ($workflowName) {
        ( my $wfWeb, $workflowName ) =
          Foswiki::Func::normalizeWebTopicName( $web, $workflowName );

        my $workflowCID = "w:$wfWeb.$workflowName";
        my $workflow = $cache{$workflowCID};
        if ( not $workflow && Foswiki::Func::topicExists( $wfWeb, $workflowName ) ) {
            $workflow =
              new Foswiki::Plugins::KVPPlugin::Workflow( $wfWeb,
                $workflowName );
            $cache{$workflowCID} = $workflow;
        }

        if ($workflow) {
            ( $meta, $text ) =
              Foswiki::Func::readTopic( $web, $topic, $rev )
              unless defined $meta;
            $controlledTopic =
              new Foswiki::Plugins::KVPPlugin::ControlledTopic(
                $workflow, $web, $topic, $meta, $text );
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

    return if $isStateChange;

    return unless $oldTopic; # don't handle webs
    return if $oldAttachment; # nor attachments

    my $suffix = _WORKFLOWSUFFIX();
    return unless $suffix;

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

sub _WORKFLOWMETA {
    my ( $session, $attributes, $topic, $web ) = @_;

    my $rWeb = $attributes->{web} || $web;
    my $rTopic = $attributes->{topic} || $topic;
    my $rev = $attributes->{rev} || 0;
    my $alt = $attributes->{alt} || '';
    my $remove = $attributes->{nousersweb};

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
        $ret =~ s#^$Foswiki::cfg{UsersWebName}\.##g if $remove;
        return $ret;
    }
    return  $alt;
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
    my @actions;
    my $numberOfActions;
    my $transwarn = '';
    my $cs = $controlledTopic->getState();

    # Get actions and warnings
    { # scope
        my ( $tmpActions, $tmpWarnings ) = $controlledTopic->getActions();
        @actions         = @$tmpActions;
        $numberOfActions = scalar(@actions);
        my @warnings     = @$tmpWarnings;

        # build javascript to associate warnings with actions
        for( my $a = $numberOfActions-1; $a >= 0; $a-- ) {
            my $warning = $warnings[$a];
            next unless $warning;
            $warning = Foswiki::Func::expandCommonVariables("%MAKETEXT{$warning}%");
            next unless $warning;
            $warning =~ s#'#\\'#g;
            my $action = $actions[$a];
            $action =~ s#'#\\'#g;
            $transwarn .= "WORKFLOW.w['$action']='$warning';";
        }
    }

    unless ($numberOfActions) {
        return '';
        return '<span class="foswikiAlert">NO AVAILABLE ACTIONS in state '
          .$cs.'</span>' if $controlledTopic->debugging();
        return '';
    }

    my @fields = (
        CGI::hidden( 'WORKFLOWSTATE', $cs ),
        CGI::hidden( 'topic', "$web.$topic" ),

        # Use a time field to help defeat the cache
        CGI::hidden( 't', time() )
    );

    my ($allow, $suggest, $remark) = $controlledTopic->getTransitionAttributes();

    Foswiki::Func::addToZone('script', 'WORKFLOW::COMMENT', <<SCRIPT, 'JQUERYPLUGIN::FOSWIKI');
<script type="text/javascript">
WORKFLOW = function(){};
WORKFLOW.allowOption = new String("$allow");
WORKFLOW.suggestOption = new String("$suggest");
WORKFLOW.remarkOption = new String("$remark");
WORKFLOW.w = function(){};
$transwarn
</script>
<script type="text/javascript" src="%PUBURLPATH%/%SYSTEMWEB%/KVPPlugin/transitions.js"></script>
SCRIPT

    if ( $numberOfActions == 1 ) {
        push( @fields,
              "<input type='hidden' name='WORKFLOWACTION' value='"
                .$actions[0]."' />" );
        push(
            @fields,
            "<noautolink>%BUTTON{\"%MAKETEXT{$actions[0]}%\" id=\"WORKFLOWbutton\" type=\"submit\"}%</noautolink>"
        );
    }
    else {
        my %labels = map{$_ => Foswiki::Func::expandCommonVariables("\%MAKETEXT{\"$_\"}\%")} @actions;
        push(
            @fields,
            CGI::popup_menu(
                -name   => 'WORKFLOWACTION',
                -values => \@actions,
                -labels => \%labels,
                -id => 'WORKFLOWmenu',
                -style => 'float: left'
            )
        );
        push(
            @fields,
            '<noautolink>%BUTTON{"%MAKETEXT{"Change status"}%" type="submit" class="KVPChangeStatus"}%</noautolink>'
        );
    }

    push( @fields,
          "<span style=\"display: none;\" id=\"WORKFLOWchkbox\">".CGI::checkbox(
              -name => 'removeComments',
              -selected => 0,
              -value => '1',
              -label => '%MAKETEXT{delete comments}%',
              -id => 'WORKFLOWchkboxbox'
          )."</span>"
    );

    push( @fields,
        '<br /><div style="display: none" id="KVPRemark">%CLEAR%%MAKETEXT{Remarks}%:<br /><textarea name="message" cols="50" rows="3" ></textarea></div>'
    );


    my $url = Foswiki::Func::getScriptUrl(
        $pluginName, 'changeState', 'rest'
    );
    my $form =
        CGI::start_form( -method => 'POST', -action => $url , -class => 'KVPTransitionForm' )
      . join( '', @fields )
      . CGI::end_form();

    $form =~ s/\r?\n//g;    # to avoid breaking TML
    # XXX I don't know what this is supposed to break but since I can't use %BUTTON{"..."}% without handling the qouotes specially I will disable it for now. An alternative is to do something like %BUTTON(?...?)% ... s/\?/"/g...
    #    $form =~ s/"/'/g;    # to avoid breaking TML
    return $form;
}

# Tag handler
# Returns the state of the current topic.
sub _WORKFLOWSTATE {
    my ( $session, $attributes, $topic, $web ) = @_;

    ($web, $topic) = _getTopicName($attributes, $web, $topic);
    my $controlledTopic = _initTOPIC( $web, $topic );

    return '' unless $controlledTopic;
    return $controlledTopic->getState();
}

# Tag handler
sub _WORKFLOWFORK {
    my ( $session, $attributes, $topic, $web ) = @_;

    my $controlledTopic = _initTOPIC( $web, $topic );
    return '' unless $controlledTopic;

    #Check we can fork
    return '' unless ($controlledTopic->canFork());

    my $newnames;
    if (!defined $attributes->{newnames}) {
        # Old interpretation, for compatibility
        $newnames = $attributes->{_DEFAULT};
        $topic = $attributes->{topic} || $topic;
    } else {
        ($web, $topic) = _getTopicName($attributes, $web, $topic);
        $newnames = $attributes->{newnames};
    }

    my $lockdown = Foswiki::Func::isTrue($attributes->{lockdown});

    if (!Foswiki::Func::topicExists($web, $topic)) {
        return "";
        return "<span class='foswikiAlert'>WORKFLOWFORK: '$topic' does not exist</span>";
    }

    my $label = $attributes->{label} || 'Fork';
    my $title = $attributes->{title};
    $title = ($title)?"title='$title'":'';

    my $url;
    if ( $newnames ) {
        $url = Foswiki::Func::getScriptUrl( 'KVPPlugin', 'fork', 'restauth', topic=> "$web.$topic", lockdown=> $lockdown, newnames=> $newnames );
    } else {
        $url = Foswiki::Func::getScriptUrl( 'KVPPlugin', 'fork', 'restauth', topic=> "$web.$topic", lockdown=> $lockdown );
    }

    # Add script to prevent double-clicking link
    my $js = Foswiki::Func::getPubUrlPath()."/$Foswiki::cfg{SystemWebName}/KVPPlugin/blockLink.js";
    Foswiki::Func::addToZone('script', 'WORKFLOW::DISABLE', "<script type=\"text/javascript\" src=\"$js\"></script>", 'JQUERYPLUGIN::FOSWIKI');
    Foswiki::Plugins::JQueryPlugin::createPlugin( 'blockUI', $session );

    return "<a class=\"kvpForkLink\" href='$url' $title>$label</a>";
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
    return $controlledTopic->getRow( $param ) if $controlledTopic;

    # Not cotrolled get row from values in configure
    my $configure = $Foswiki::cfg{Extensions}{KVPPlugin}{uncontrolledRow};
    return '' unless $configure;
    return $configure->{$param} || '';
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

    my $web   = $query->param('web') || $session->{webName};
    my $topic = $query->param('topic') || $session->{topicName};
    my $remark = $query->param('message');
    my $removeComments = $query->param('removeComments') || '0';
    my $action = $query->param('WORKFLOWACTION');
    my $state  = $query->param('WORKFLOWSTATE');
    
    ($web, $topic) =
      Foswiki::Func::normalizeWebTopicName( $web, $topic );
    
    die unless $web && $topic;

    my $url;
    my $controlledTopic = _initTOPIC( $web, $topic );

    unless ($controlledTopic && Foswiki::Func::topicExists( $web, $topic )) {
        $url = Foswiki::Func::getScriptUrl(
            $web, $topic, 'oops',
            template => "oopswrkflwsaveerr",
            action   => $action
        );
        Foswiki::Func::redirectCgiQuery( undef, $url );
        return undef;
    }

    my $oldIsApproved = $controlledTopic->getRow( "approved" );

    unless ($action
            && $state
            && $state eq $controlledTopic->getState()
            && $controlledTopic->haveNextState($action) ) {
        $url = Foswiki::Func::getScriptUrl(
            $web, $topic, 'oops',
            template => "oopswrkflwsaveerr",
            state   => $state,
            cstate   => $controlledTopic->getState(),
            action   => $action
        );
        Foswiki::Func::redirectCgiQuery( undef, $url );
        return undef;
    }

    my $newForm = $controlledTopic->newForm($action);

    # Check that no-one else has a lease on the topic
    my $breaklock = $query->param('breaklock');
    unless (Foswiki::Func::isTrue($breaklock)) {
        my ( $url, $loginName, $t ) = Foswiki::Func::checkTopicEditLock(
            $web, $topic
        );
        if ( $t ) {
            my $currUser = Foswiki::Func::getCanonicalUserID();
            my $locker = Foswiki::Func::getCanonicalUserID($loginName);
            if ($locker ne $currUser) {
                $t = Foswiki::Time::formatDelta(
                    $t, $Foswiki::Plugins::SESSION->i18n
                );
                $remark =~ s#"#&quot;#;
                $url = Foswiki::Func::getScriptUrl(
                    $web, $topic, 'oops',
                    template => 'oopswfplease',
                    param1   => Foswiki::Func::getWikiName($locker),
                    param2   => $t,
                    param3   => $state,
                    param4   => $action,
                    param5   => $remark,
                    param6   => $removeComments
                   );
                Foswiki::Func::redirectCgiQuery( undef, $url );
                return undef;
            }
        }
    }

    try {
        try {
            #Alex: Forms erstmal vorenthalten
            if ($newForm && "peter" eq "manni") {

                # If there is a form with the new state, and it's not
                # the same form as previously, we need to kick into edit
                # mode to support form field changes. In this case the
                # transition is delayed until after the edit is saved
                # (the transition is executed by the beforeSaveHandler)
                $url =
                  Foswiki::Func::getScriptUrl(
                      $web, $topic, 'edit',
                      breaklock             => $breaklock,
                      t                     => time(),
                      formtemplate          => $newForm,
                      # pass info about pending state change
                      template              => 'workflowedit',
                      WORKFLOWPENDINGACTION => $action,
                      WORKFLOWCURRENTSTATE  => $state,
                      WORKFLOWPENDINGSTATE  =>
                        $controlledTopic->haveNextState($action),
                      WORKFLOWWORKFLOW      =>
                        $controlledTopic->{workflow}->{name},
                     );
            }
            else {
                $url = Foswiki::Func::getScriptUrl( $web, $topic, 'view' );
            }

            # Get ForkingAction. This will determine, if discussion will be copied, overwritten or discarded
            my $actionAttributes = $controlledTopic->getAttributes($action) || '';
            $actionAttributes =~ /(?:\W|^)(FORK|DISCARD)(?:\W|$)/;
            my $forkingAction = $1;

            # clear message, if workflow doesn't allow it (maybe the
            # user entered a message and then switched state...)
            if( $actionAttributes !~ /(?:\W|^)REMARK(?:\W|$)/ ) {
                $remark = '';
            }

            # check if deleting comments is allowed if requested
            { #scope
                my ($allowRemove, $suggestRemove) = $controlledTopic->getTransitionAttributes();
                if(
                        $removeComments eq '1' 
                        && not ($allowRemove =~ /,$action,/ || $suggestRemove =~ /,$action,/)
                    )
                {
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
            $controlledTopic->changeState($action, $remark);

            # Flag that this is a state change to the beforeSaveHandler (beforeRenameHandler)
            local $isStateChange = 1;
            #Alex: Zugehriges Topic finden
            my $appTopic = $originCache;

            # Hier Action 
            if ($forkingAction && $forkingAction eq "DISCARD") {
                $controlledTopic->purgeContributors(); # XXX Wirklich?
                my $origMeta = $controlledTopic->{meta};

                # Move topic to trash
                $controlledTopic->save(1);
                _trashTopic($web, $topic);

                # Only unlock / add to history if web exists (does not when topic)
                if(Foswiki::Func::topicExists( $web, $appTopic )) {
                    $url = Foswiki::Func::getScriptUrl( $web, $appTopic, 'view' );

                    #Alex: Alte Metadaten wiederherstellen
                    my ($meta, $text) = Foswiki::Func::readTopic($web, $appTopic);

                    #gesperrte Seiten wieder entsperren
                    if (defined $meta->get("PREFERENCE", "ALLOWTOPICCHANGE")){
                        if ($meta->get("PREFERENCE", "ALLOWTOPICCHANGE")->{"value"} eq "nobody")
                        {# XXX Hier muessen die permissions aus dem Workflow hin
                            $meta->remove("PREFERENCE", "ALLOWTOPICCHANGE"); 
                        }
                    }
                    #Workflowhistory entfernen. Alex: Oder wollen wir die ggf. speichern?
                    if (defined $meta->get("WORKFLOWHISTORY")){
                        $meta->remove("WORKFLOWHISTORY"); 
                    }

                    #Alex: Keine neue Revision erzeugen, Autor nicht ueberschreiben
                    Foswiki::Func::saveTopic( 
                        $web, $appTopic, $meta, $text,
                        { forcenewrevision => 0, minor => 1, dontlog => 1, ignorepermissions => 1 }
                    );
                } else {
                    # if non-talk topic does not exist redirect to parent
                    my $parent = $origMeta->getParent();
                    my $parentWeb = $origMeta->web();
                    $url = Foswiki::Func::getViewUrl($parentWeb, $parent);
                }
            }
            # Check if discussion is beeing accepted
            elsif (!$oldIsApproved && $controlledTopic->getRow("approved")) {
                # transfer ACLs from old document to new
                transferACL($web, $appTopic, $controlledTopic);
                $controlledTopic->purgeContributors();
                $controlledTopic->nextRev() unless $actionAttributes =~ m#NOREV#;
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
                    Foswiki::Func::moveTopic( $web, $topic, $web, $appTopic );
                }
            }
            else{
                $controlledTopic->nextRev() if $actionAttributes =~ m#NEXTREV#;
                $controlledTopic->save(1);
            }

            Foswiki::Func::redirectCgiQuery( undef, $url );
            
        } catch Error::Simple with {
            my $error = shift;
            throw Foswiki::OopsException(
                'oopssaveerr',
                web    => $web,
                topic  => $topic,
                params => [ $error || '?' ]
               );
        };
    } catch Foswiki::OopsException with {
        my $e = shift;
        if ( $e->can('generate') ) {
            $e->generate($session);
        }
        else {

            # Deprecated, TWiki compatibility only
            $e->redirect($session);
        }
    };
    return undef;
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
            $url = Foswiki::Func::getViewUrl($web, $topic);
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
        my $origin = $originCache;
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

sub _restFork {
    my ($session, $plugin, $verb, $response) = @_; 
    # Update the history in the template topic and the new topic
    my $query = Foswiki::Func::getCgiQuery();
    my $forkTopic = $query->param('topic');
    my @newnames = split(/,/, $query->param('newnames') || $forkTopic.(_WORKFLOWSUFFIX()));
    my $lockdown = $query->param('lockdown');

    my $erroneous = '';

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
        my $defaultAction = $controlledTopic->getActionWithAttribute('FORK');

        my ($ttmeta, $tttext) = Foswiki::Func::readTopic(
            $forkWeb, $forkTopic);

        my $now = Foswiki::Func::formatTime( time(), undef, 'servertime' );
        my $who = Foswiki::Func::getWikiUserName();

        # Default to topicTALKSUFFIX if no newnames are given, the action is valid.
        if ( scalar @newnames == 0 ) {
            my $forkSuffix = _WORKFLOWSUFFIX();
            @newnames = ($forkTopic.$forkSuffix);
        }

        my (@webs, @topics, @actions) = ((), (), ());

        # First find out topicnames and actions.
        # In case of an error return without having changed anything in the wiki.
        foreach my $newname (@newnames) {

            # Get name for new topic and action to execute
            my ($newWeb, $newTopic, $newAction);
            if ( $newname =~ m/\s*\[(.*)\]\[(.*)\]\s*/ ) {
                ($newTopic, $newAction) = ($1, $2);
                ($newWeb, $newTopic) = Foswiki::Func::normalizeWebTopicName( $forkWeb, $newTopic );
                unless (
                        Foswiki::Func::isValidTopicName( $newTopic, 1 ) &&
                        Foswiki::Func::isValidWebName( $newWeb ) ) {
                    $erroneous .= '%MAKETEXT{"Invalid destination to fork to: [_1]" args="'."'$newWeb.$newTopic'\"}%\n\n";
                    next;
                }
                unless ( $controlledTopic->haveNextState($newAction) ) {
                    $erroneous .= '%MAKETEXT{"Cannot execute transition =[_1]= on =[_2]= (invalid on source-workflow)!" args="'."$newAction, $forkWeb.$forkTopic\"}%\n\n";
                    next;
                }
                # check if action allowed in targetworkflow
                my $targetControlledTopic = _initTOPIC( $newWeb, $newTopic, undef, $ttmeta, $tttext, FORCENEW);
                unless( $targetControlledTopic && $targetControlledTopic->haveNextState($newAction) ) {
                    $erroneous .= '%MAKETEXT{"Cannot execute transition =[_1]= on =[_2]= (invalid on target-workflow)!" args="'."$newAction, $newWeb.$newTopic\"}%\n\n";
                    next;
                }
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
        }

        # Now copy the topics and do the transitions.    
        unless ($erroneous) { 
            while (scalar @topics) {
                my $newTopic = shift @topics;
                my $newAction = shift @actions;
                my $newWeb = shift @webs;

                $directToWeb = $newWeb;
                $directToTopic = $newTopic;

                next if (Foswiki::Func::topicExists($newWeb, $newTopic)); 

                #Alex: Topic mit allen Dateien kopieren
                my $handler = $session->{store}->getHandler( $forkWeb, $forkTopic );
                $handler->copyTopic($session->{store}, $newWeb, $newTopic);

                my $text = $tttext;
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
                    value => "<br>Forked from [[$forkWeb.$forkTopic]] by $who at $now",
                };
                $meta->put( "WORKFLOWHISTORY", $forkhistory );

                my $history = $ttmeta->get('WORKFLOWHISTORY') || {};
                $history->{value} .= "<br>Forked to " .
                    "[[$newWeb.$newTopic]]" . " by $who at $now";
                $ttmeta->put( "WORKFLOWHISTORY", $history );

                # Modell Aachen Settings:
                # Ueberfuehren in Underrevision:    
                my $newcontrolledTopic = _initTOPIC( $newWeb, $newTopic, undef, $meta, $text, FORCENEW);

                unless ( $newcontrolledTopic ) {
                    $erroneous .= '%MAKETEXT{"Could not initialize workflow for"}% '."$newWeb.$newTopic\n\n";
                    next; # XXX this leaves the created topic behind
                }

                $newcontrolledTopic->changeState($newAction);
                local $isStateChange = 1;
                $newcontrolledTopic->save(1);
                local $isStateChange = 0;

                # Topic successfully forked
            }

            if ($lockdown) {
                $ttmeta->putKeyed("PREFERENCE",
                    { name => 'ALLOWTOPICCHANGE', value => 'nobody' });
            }

            # Modac: Save old Topic
            local $isStateChange = 1;
            Foswiki::Func::saveTopic( $forkWeb, $forkTopic, $ttmeta, $tttext,
                    { forcenewrevision => 1, ignorepermissions => 1 });
            local $isStateChange = 0;
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

    #redirect to last successfully forked topic
    return $response->redirect(Foswiki::Func::getViewUrl($directToWeb, $directToTopic));
}

# XXX requires changes in lib/Foswiki/Meta.pm
# Will check if the workflow permits the user to move topics and rename attachments.
sub beforeRenameHandler {
    my( $oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment ) = @_;

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
    my ($meta, $text) = Foswiki::Func::readTopic($oldWeb, $oldTopic);
    my $newControlledTopic = _initTOPIC( $newWeb, $newTopic, undef, $meta, $text, 1);
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

    # Check the state change parameters to see if this edit is
    # part of a state change (state changes may be permitted even
    # for users who can't edit, so we have to suppress the edit
    # check in this case)
    my $changingState = 1;
    my $query = Foswiki::Func::getCgiQuery();
    foreach my $p ('WORKFLOWPENDINGACTION', 'WORKFLOWCURRENTSTATE',
                     'WORKFLOWPENDINGSTATE', 'WORKFLOWWORKFLOW') {
        if (!defined $query->param($p)) {
            # All params must be present to change state
            $changingState = 0;
            last;
        }
    }

    return if $changingState; # permissions check not required

    my $controlledTopic = _initTOPIC( $web, $topic );

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
sub beforeUploadHandler {
    my ( $attrs, $meta ) = @_;

    my $web = $meta->web();
    my $topic = $meta->topic();

    my $controlledTopic = _initTOPIC( $web, $topic );
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
        $meta->putKeyed('PREFERENCE', { name => 'WorkflowStub', title=>'WorkflowStub', type=>'Set', value=>'1' });
    }
}

# The beforeSaveHandler inspects the request parameters to see if the
# right params are present to trigger a state change. The legality of
# the state change is *not* checked - it's assumed that the change is
# coming as the result of an edit invoked by a state transition.
sub beforeSaveHandler {
    my ( $text, $topic, $web, $meta ) = @_;

    my $query = Foswiki::Func::getCgiQuery();
    return if($query->url() =~ m#/bin/jsonrpc$#); # XXX always pass MetaCommentPlugin

    # Do the RemoveMeta, RemovePref, SetForm, SetField, SetPref if save came from a template
    if($query->param('templatetopic')) {
        # Got to get those values now, or they might be removed
        my $removeMeta = $meta->get( 'PREFERENCE', 'RemoveMeta' );
        my $removePref = $meta->get( 'PREFERENCE', 'RemovePref' );
        my $setForm = $meta->get( 'PREFERENCE', 'SetForm' );
        my $setField = $meta->get( 'PREFERENCE', 'SetField' );
        my $setMeta = $meta->get( 'PREFERENCE', 'SetPref' );

        # We don't ever want to copy over the workflow state from a template
        $meta->remove('WORKFLOW');
        $meta->remove('WORKFLOWHISTORY');
        $meta->remove('WRKFLWCONTRIBUTORS');

        # First set stuff, as it might require values that are to be removed.
        # SetForm:
        if($setForm) {
            $meta->remove('PREFERENCE', 'SetForm');
            $setForm = Foswiki::Func::expandCommonVariables(
                $setForm->{value}, $topic, $web, $meta);
            $setForm =~ s#^\s*##g;
            $setForm =~ s#\s*$##g;
            $meta->put('FORM', { name => $setForm } );
        }
        # SetField:
        if($setField) {
            $meta->remove('PREFERENCE', 'SetField');
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
        # SetPref:
        my $removePrefChanged = 0; # Remember if RemovePref has been changed
        if($setMeta) {
            $meta->remove('PREFERENCE', 'SetPref');
            $setMeta = Foswiki::Func::expandCommonVariables(
                $setMeta->{value}, $topic, $web, $meta
            );
            while($setMeta =~ m/"\s*([^"]+?)\s*=\s*([^"]*?)\s*"/g) {
                my $toSet = $1;
                my $value = $2;
                $value =~ s#\$quot#"#g;
                $value =~ s#\$dollar#\$#g;
                $meta->putKeyed(
                    'PREFERENCE',
                    { name => $toSet, title => $toSet, type => 'Set', value => $value }
                );
                $removePrefChanged = 1 if ($toSet eq "RemovePref");
            }
        }
        # RemoveMeta:
        if($removeMeta) {
            $meta->remove('PREFERENCE', 'RemoveMeta');
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
        # RemovePref:
        if($removePref) {
            $meta->remove('PREFERENCE', 'RemovePref') unless $removePrefChanged;
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
    }

    # $isStateChange is true if state has just been changed in this session.
    # In this case we don't need the access check.
    return if ($isStateChange);

    my $oldControlledTopic = _initTOPIC( $web, $topic, undef, undef, undef, NOCACHE );
    my $controlledTopic = _initTOPIC( $web, $topic, undef, $meta, $text, FORCENEW );

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
            my $message = Foswiki::Func::expandCommonVariables('%MAKETEXT{"Must find exactly one workflow in the topic, but found [_1]!" args="'.scalar(@newStateName).'"}%', $topic, $web, $meta);
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
            
            my $oldMeta = $controlledTopic->{meta};
            my $oldState = $oldMeta->get( 'WORKFLOW' );
            unless($newStateName[0]->{name} eq $oldState->{name}) {
                my $message = Foswiki::Func::expandCommonVariables('%MAKETEXT{"The Workflowstate =[_1]= does not match the old state =[_2]=...maybe someone edited the topic after you opened it? Topic cannot be saved!" args="'."$newStateName[0]->{name},$oldState->{name}\"}%", $topic, $web, $meta);
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
        } else {
            # This topic is now no longer a stub.
            $controlledTopic->{meta}->remove('PREFERENCE', 'WorkflowStub');
            # XXX This check does not work properly
            # Make sure that newly created topics can't cheat with their state
            if(scalar @newStateName > 1) { # If 0 this is a new topic, or not controlled, if it's a copy it may be 1.
                my $message = Foswiki::Func::expandCommonVariables('%MAKETEXT{"Found an invalid workflow (there must be none in a newly created topic)!"}%');
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
                my $newAction = $controlledTopic->getActionWithAttribute('NEW');
                if($newAction) {
                    $controlledTopic->changeState($newAction);
                } elsif ( not ( Foswiki::Func::isAnAdmin() || $Foswiki::cfg{Extensions}{KVPPlugin}{NoNewRequired} ) ) {
                    my $message = Foswiki::Func::expandCommonVariables('%MAKETEXT{"You may not create this topic under this workflow!"}%');
                    throw Foswiki::OopsException(
                        'workflowerr',
                        def => 'topic_creation',
                        web => $web,
                        topic => $topic,
                        params => $message
                    );
                }
        }
    }

    $controlledTopic->addContributors(Foswiki::Func::getWikiUserName());
}

sub indexTopicHandler {
    my ($indexer, $doc, $web, $topic, $meta, $text) = @_;

    # only index controlled topics, or old metadata will end up in index.
    # XXX would be cool if one could detect when a workflow failed to parse
    my $controlledTopic = _initTOPIC( $web, $topic, undef, $meta, $text, NOCACHE );

    if( $controlledTopic ) {
        $doc->add_fields( workflow_controlled_b => 1 );
    } else {
        $doc->add_fields( workflow_controlled_b => 0 );
        return;
    }

    # might result in default-state
    my $state = $controlledTopic->getState();
    $doc->add_fields( process_state_s => $state) if $state;

    $doc->add_fields( workflow_isapproved_b => ($controlledTopic->getRow( 'approved' ))?1:0 );

    # Modac : Mega Easy Implementation
    my $workflow = $meta->get('WORKFLOW');
    return unless $workflow; # might happen when topics are created outside workflow and then move into a workflowed web

    # provide ALL the fields
    for my $key (keys %$workflow) {
        $doc->add_fields("workflowmeta_". lc($key) ."_s" => $workflow->{$key});
    }

    # Contributors
    my @cHashes = $controlledTopic->{meta}->find('WRKFLWCONTRIBUTORS');
    foreach my $contis (@cHashes) {
        my $field = 'workflow_contributors_'.lc($contis->{name}).'_lst';
        foreach my $person (split(',', $contis->{value})) {
            $doc->add_fields( $field => $person);
        }
    }

    my $suffix = _WORKFLOWSUFFIX();
    $doc->add_fields( workflow_hasdiscussion_b => Foswiki::Func::topicExists($web, "$topic$suffix")?1:0 );

    # mild sanity-test if state exists (eg. Workflow-table changed and state got renamed)
    if($controlledTopic && not $controlledTopic->getRow('state') eq $state) {
        Foswiki::Func::writeWarning("Workflow error in $web.$topic");
        $doc->add_fields( workflow_tasked_lst => 'KvpError' );
    }

    # index tasks
    if($workflow->{TASK}) {
        my $taskedPeople = $controlledTopic->getTaskedPeople();
        unless ($taskedPeople && scalar @$taskedPeople) {
            $doc->add_fields( workflow_tasked_lst => 'KvpTaskedNobody' );
            return;
        }
        foreach my $user ( @$taskedPeople ) {
            $doc->add_fields( workflow_tasked_lst => $user );
            if( $Foswiki::cfg{Extensions}{KVPPlugin}{MonitorTasked}
                    && not Foswiki::Func::wikiToUserName( $user ) ) {
                $doc->add_fields( workflow_tasked_lst => 'KvpUnknownUser' );
            }
        }
    }
}

1;
__END__

 Copyright (C) 2005 Thomas Hartkens <thomas@hartkens.de>
 Copyright (C) 2005 Thomas Weigert <thomas.weigert@motorola.com>
 Copyright (C) 2008-2010 Crawford Currie http://c-dot.co.uk

 This program is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation; either version 2
 of the License, or (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details, published at
 http://www.gnu.org/copyleft/gpl.html
