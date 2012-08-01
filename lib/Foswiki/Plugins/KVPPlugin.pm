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

our $VERSION          = '$Rev: 7808 (2010-06-15) $';
our $RELEASE          = '1.5.6';
our $SHORTDESCRIPTION = 'Kontinuierliche Verbesserung im Wiki';
our $NO_PREFS_IN_TOPIC = 1;
our $pluginName       = 'KVPPlugin';
our %cache;
our $isStateChange;

sub initPlugin {
    my ( $topic, $web ) = @_;

    %cache = ();

    Foswiki::Func::registerRESTHandler(
        'changeState', \&_changeState,
        http_allow => 'POST' );
    Foswiki::Func::registerRESTHandler(
        'fork', \&_restFork,
        authenticate => 1, http_allow => 'GET' );

    Foswiki::Func::registerTagHandler(
        'WORKFLOWSTATE', \&_WORKFLOWSTATE );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWEDITTOPIC', \&_WORKFLOWEDITTOPIC );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWATTACHTOPIC', \&_WORKFLOWATTACHTOPIC );
    Foswiki::Func::registerTagHandler(
        'WORKFLOWSTATEMESSAGE', \&_WORKFLOWSTATEMESSAGE );
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

    my $controlledTopic = _initTOPIC( $web, $topic );
    if ($controlledTopic) {
        my $context = Foswiki::Func::getContext();
        $context->{'KVPControlled'} = 1;
	if ($controlledTopic->canEdit()) {
            $context->{'KVPEdit'} = 1;
        }
	unless ($controlledTopic->getRow( 'approved' )) {
            $context->{'KVPDiscussion'} = 1;
        }
    }

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

# Tag handler for WORKFLOWEDITPERM
# Will return 1 if the user is allowed to edit this topic
sub _WORKFLOWEDITPERM {
    my ( $session, $params, $topic, $web ) = @_;

    my $controlledTopic = _initTOPIC( $web, $topic );
    if ($controlledTopic) {
        return $controlledTopic->canEdit() ? 1 : 0;
    }
    # No workflow...
    # Does Foswiki permit editing?
    return Foswiki::Func::checkAccessPermission(
        'CHANGE', $Foswiki::Plugins::SESSION->{user},
        undef, $topic, $web, undef) ? 1 : 0;
}

# Tag handler for WORKFLOWCONTRIBUTORS
# Will return a list of users that have contributed to this topic until last ACCEPT.
sub _WORKFLOWCONTRIBUTORS {
    my ( $session, $params, $topic, $web ) = @_;
    my $controlledTopic = _initTOPIC( $web, $topic );

    return unless $controlledTopic;
    return $controlledTopic->getExtraNotify();
}

# XXX Copy/Paste from Workflow::_isAllowed
# Checks if the User is in a list
sub isInList {
    my ($allow) = @_;
    if ( ref( $Foswiki::Plugins::SESSION->{user} )
        && $Foswiki::Plugins::SESSION->{user}->can("isInList") )
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
        Foswiki::Func::writeWarning("No Suffix defined! Defaulting to Talk!");
        $forkSuffix = 'Talk';
    }
    return $forkSuffix;
}

# Tag handler, returns the topicname without suffix
sub _WORKFLOWORIGIN {
    my ( $session, $attributes, $topic, $web ) = @_;
    my $suffix = _WORKFLOWSUFFIX();
    if($topic =~ /(.*)$suffix/) {
      return $1;
    } else {
      return $topic;
    }
}

sub _initTOPIC {
    my ( $web, $topic, $rev, $meta, $text, $forceNew ) = @_;

    # Skip system web for performance
    if($web eq "System") {return undef;}

    # Filter out topics inhibited in configure
    my $exceptions = $Foswiki::cfg{Extensions}{KVPPlugin}{except};
    return undef if $exceptions && $topic =~ /$exceptions/;

    $rev ||= 99999;    # latest

    ( $web, $topic ) = Foswiki::Func::normalizeWebTopicName( $web, $topic );
    return undef unless(Foswiki::Func::isValidWebName( $web ));
    
    my $controlledTopic;

    unless ($forceNew) {
        $controlledTopic = $cache{"$web.$topic.$rev"};
        if ($controlledTopic) {
            return if $controlledTopic eq '_undef';
            return $controlledTopic;
        }
    }

    if ( defined &Foswiki::Func::isValidTopicName ) {

        # Allow non-wikiwords
        return undef unless Foswiki::Func::isValidTopicName( $topic, 1 );
    }
    else {

        # (tm)wiki doesn't have isValidTopicName
        # best we can do
        return undef unless Foswiki::Func::isValidWikiWord($topic);
    }

    Foswiki::Func::pushTopicContext( $web, $topic );
    my $workflowName = Foswiki::Func::getPreferencesValue('WORKFLOW');
    Foswiki::Func::popTopicContext( $web, $topic );

    if ($workflowName) {
        ( my $wfWeb, $workflowName ) =
          Foswiki::Func::normalizeWebTopicName( $web, $workflowName );

        if ( Foswiki::Func::topicExists( $wfWeb, $workflowName ) ) {
            my $workflow =
              new Foswiki::Plugins::KVPPlugin::Workflow( $wfWeb,
                $workflowName );

            if ($workflow) {
                ( $meta, $text ) =
                  Foswiki::Func::readTopic( $web, $topic, $rev )
                  unless defined $meta;
                $controlledTopic =
                  new Foswiki::Plugins::KVPPlugin::ControlledTopic(
                    $workflow, $web, $topic, $meta, $text );
            }
        }
    }

    $cache{"$web.$topic.$rev"} = $controlledTopic || '_undef';
    return $controlledTopic;
}

sub _getTopicName {
    my ($attributes, $web, $topic) = @_;

    return Foswiki::Func::normalizeWebTopicName(
        $attributes->{web} || $web,
        $attributes->{_DEFAULT} || $topic );
}

# Tag handler
sub _WORKFLOWEDITTOPIC {
    my ( $session, $attributes, $topic, $web ) = @_;

    ($web, $topic) = _getTopicName($attributes, $web, $topic);
    my $controlledTopic = _initTOPIC( $web, $topic );
    
    #Editieren zulassen, falls nicht kontrolliertes Topic
    unless ($controlledTopic) {
    	return CGI::a(
            {
                href => Foswiki::Func::getScriptUrl(
                    $web, $topic, 'edit',
                    t => time() ),
            },
            '%MAKETEXT{"Edit"}%' );
    }

    # replace edit tag
    if ( $controlledTopic->canEdit() ) {
        return CGI::a(
            {
                href => Foswiki::Func::getScriptUrl(
                    $web, $topic, 'edit',
                    t => time() ),
            },
            '%MAKETEXT{"Edit"}%' );
    }
    else {
        return "";
    }
}

# Tag handler
sub _WORKFLOWSTATEMESSAGE {
    my ( $session, $attributes, $topic, $web ) = @_;

    ($web, $topic) = _getTopicName($attributes, $web, $topic);
    my $controlledTopic = _initTOPIC( $web, $topic );
    return '' unless $controlledTopic;

    return $controlledTopic->getStateMessage();
}

# Tag handler
sub _WORKFLOWATTACHTOPIC {
    my ( $session, $attributes, $topic, $web ) = @_;

    ($web, $topic) = _getTopicName($attributes, $web, $topic);
    my $controlledTopic = _initTOPIC( $web, $topic );
    unless ($controlledTopic) {
    	        return CGI::a(
            {
                href => Foswiki::Func::getScriptUrl(
                    $web, $topic, 'attach', t => time()
                )
            },
            '%MAKETEXT{"Attachments"}%'
        );
    }

    # replace attach tag
    if ( $controlledTopic->canAttach() ) {
        return CGI::a(
            {
                href => Foswiki::Func::getScriptUrl(
                    $web, $topic, 'attach', t => time()
                )
            },
            '%MAKETEXT{"Attachments"}%'
        );
    }
    else {
        return "";
    }
}

# Tag handler
sub _WORKFLOWHISTORY {
    my ( $session, $attributes, $topic, $web ) = @_;

    ($web, $topic) = _getTopicName($attributes, $web, $topic);
    my $controlledTopic = _initTOPIC( $web, $topic );
    return '' unless $controlledTopic;

    return $controlledTopic->getHistoryText();
}

sub _WORKFLOWMETA {
    my ( $session, $attributes, $topic, $web ) = @_;

    my $rWeb = $attributes->{web} || $web;
    my $rTopic = $attributes->{topic} || $topic;
    my $rev = $attributes->{rev} || 0;
    my $alt = $attributes->{alt} || '';
    my $remove = $attributes->{nousersweb};

    my $attr;
    my $controlledTopic = _initTOPIC( $web, $topic, $rev );
    return $alt unless $controlledTopic;
    
    if (!defined $attributes->{name}) {
        # Old interpretation, for compatibility
        $attr = $attributes->{_DEFAULT};
    } else {
        $attr = $attributes->{name};
    }
    $attr ||= 'name';

    my $ret = $controlledTopic->getWorkflowMeta($attr);
    if(!$ret) {
        my $list = $attributes->{or};
	if($list) {
            while(!$ret && $list =~ m/([a-zA-Z_]*)/g) {
                $ret = $controlledTopic->getWorkflowMeta($1);
            }
        }
    }
    if($ret) {
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

    #
    # Build the button to change the current status
    #
    my @actions         = $controlledTopic->getActions();
    my $numberOfActions = scalar(@actions);
    my $cs              = $controlledTopic->getState();

    unless ($numberOfActions) {
    	return '';
        return '<span class="foswikiAlert">NO AVAILABLE ACTIONS in state '
          .$cs.'</span>' if $controlledTopic->debugging();
        return '';
    }

    my @fields = (
        CGI::hidden( 'WORKFLOWSTATE', $cs ),
        CGI::hidden( 'topic',         "$web.$topic" ),

        # Use a time field to help defeat the cache
        CGI::hidden( 't', time() )
    );
    
    my $buttonClass =
      Foswiki::Func::getPreferencesValue('WORKFLOWTRANSITIONCSSCLASS')
          || 'foswikiChangeFormButton foswikiSubmit"';

    my ($allow, $suggest) = $controlledTopic->getDelActions();
    
    Foswiki::Func::addToZone('script', 'WORKFLOW::COMMENT', <<SCRIPT, 'JQUERYPLUGIN::FOSWIKI');
<script type="text/javascript">
\$(document).ready(function() {
  WORKFLOWallowOption = new String("$allow");
  WORKFLOWsuggestOption = new String("$suggest");
  WORKFLOWshowCheckBox = function() {
      var menu = \$('#WORKFLOWmenu');
      var selection = menu.val(); 
      if(selection === undefined) {
          menu = \$('#WORKFLOWbutton');
          if (menu === undefined) return;
          selection = menu.val();
      }
      var box = document.getElementById("WORKFLOWchkbox");
      if (box === undefined || box === null) return;
      if(WORKFLOWallowOption.indexOf(','+selection+',') > -1) {
          box.style.display = 'inline';
          document.getElementById('WORKFLOWchkboxbox').checked = false;
      } else if (WORKFLOWsuggestOption.indexOf(','+selection+',') > -1) {
          box.style.display = 'inline';
          document.getElementById('WORKFLOWchkboxbox').checked = true;
      } else {
          box.style.display = 'none';
      }
  }
\$('select').change(WORKFLOWshowCheckBox);
WORKFLOWshowCheckBox();
});
</script>
SCRIPT

    if ( $numberOfActions == 1 ) {
        push( @fields,
              "<input type='hidden' name='WORKFLOWACTION' value='"
                .$actions[0]."' />" );
        push(
            @fields,
#            CGI::submit(
#                -class => $buttonClass,
#                -value => $actions[0],
#                -id => 'WORKFLOWbutton'
#            )
            "<noautolink>%BUTTON{\"%MAKETEXT{$actions[0]}%\" id=\"WORKFLOWbutton\" type=\"submit\" onclick=\"jQuery('#KVPTransitions').block()\"}%</noautolink>"
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
#            CGI::submit(
#                -class => $buttonClass,
#                -value => 'Change status'
#            )
            "<noautolink>%BUTTON{\"%MAKETEXT{\"Change status\"}%\" type=\"submit\" onclick=\"jQuery('#KVPTransitions').block()\"}%</noautolink>"
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


    my $url = Foswiki::Func::getScriptUrl(
        $pluginName, 'changeState', 'rest' );
    my $form =
        CGI::start_form( -method => 'POST', -action => $url )
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
    my $buttonClass =
      Foswiki::Func::getPreferencesValue('WORKFLOWTRANSITIONCSSCLASS')
      || 'foswikiChangeFormButton foswikiSubmit"';
      
    my $url;
    if ( $newnames ) {
        $url = Foswiki::Func::getScriptUrl( 'KVPPlugin', 'fork', 'rest', topic=> "$web.$topic", lockdown=> $lockdown, newnames=> $newnames );
    } else {
        $url = Foswiki::Func::getScriptUrl( 'KVPPlugin', 'fork', 'rest', topic=> "$web.$topic", lockdown=> $lockdown );
    }
    
    return "<a href='$url' $title>$label</a>";
}

# Tag handler
# Return the entry of the given row for the current topic in it's current state.
sub _GETWORKFLOWROW {
    my ( $session, $attributes, $topic, $web ) = @_;
    my $param = $attributes->{_DEFAULT};

    my $controlledTopic = _initTOPIC ($web, $topic );
    return $controlledTopic->getRow( $param ) if $controlledTopic;

    # Not cotrolled get row from values in configure
    my $configure = $Foswiki::cfg{Extensions}{KVPPlugin}{uncontrolledRow};
    return '' unless $configure;
    return $configure->{$param};
}

# Handle actions. REST handler, on changeState action.
sub _changeState {
    my ($session) = @_;
    
    my $query = Foswiki::Func::getCgiQuery();
    
    return unless $query;
	
    my $web   = $query->param('web') || $session->{webName};
    my $topic = $query->param('topic') || $session->{topicName};
    my $removeComments = $query->param('removeComments') || '0';
    
    ($web, $topic) =
      Foswiki::Func::normalizeWebTopicName( $web, $topic );
    
    die unless $web && $topic;

    my $url;
    my $controlledTopic = _initTOPIC( $web, $topic );

    unless ($controlledTopic) {
        $url = Foswiki::Func::getScriptUrl(
            $web, $topic, 'oops',
            template => "oopssaveerr",
            param1   => "Could not initialise workflow for "
              . ( $web   || '' ) . '.'
                . ( $topic || '' )
               );
        Foswiki::Func::redirectCgiQuery( undef, $url );
        return undef;
    }

    my $action = $query->param('WORKFLOWACTION');
    my $state  = $query->param('WORKFLOWSTATE');
    
    #Alex: Die Bad State ist nicht schön
    die "BAD STATE $action $state!=", $controlledTopic->getState()
      unless $action
        && $state
          && $state eq $controlledTopic->getState()
            && $controlledTopic->haveNextState($action);

    my $newForm = $controlledTopic->newForm($action);

    # Check that no-one else has a lease on the topic
    my $breaklock = $query->param('breaklock');
    unless (Foswiki::Func::isTrue($breaklock)) {
        my ( $url, $loginName, $t ) = Foswiki::Func::checkTopicEditLock(
            $web, $topic );
        if ( $t ) {
            my $currUser = Foswiki::Func::getCanonicalUserID();
            my $locker = Foswiki::Func::getCanonicalUserID($loginName);
            if ($locker ne $currUser) {
                $t = Foswiki::Time::formatDelta(
                    $t, $Foswiki::Plugins::SESSION->i18n );
                $url = Foswiki::Func::getScriptUrl(
                    $web, $topic, 'oops',
                    template => 'oopswfplease',
                    param1   => Foswiki::Func::getWikiName($locker),
                    param2   => $t,
                    param3   => $state,
                    param4   => $action,
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
                my $forkingAction = $controlledTopic->{workflow}->getForkingAction( $controlledTopic, $action );
                $controlledTopic->changeState($action);

                # check if deleting comments is allowed if requested
                { #scope
                    my ($allowRemove, $suggestRemove) = $controlledTopic->getDelActions();
                    if( $removeComments eq '1' 
                        && not ($allowRemove =~ /,$action,/ || $suggestRemove =~ /,$action,/)
                    ) {
                        my $username = Foswiki::Func::getWikiUserName();
                        Foswiki::Func::writeWarning("User ".$username." tryed to remove all comments althought the action ".$action." doesn't allow it!");
                        $removeComments = '0';
                    }
                }
                # overwrite user-choice if workflow demands it
                if($controlledTopic->isRemovingComments($state, $action)) {
                    $removeComments = '1';
                }
                removeComments($controlledTopic) if ($removeComments eq '1');

                # Flag that this is a state change to the beforeSaveHandler
                local $isStateChange = 1;
                #Alex: Zugehöriges Topic finden
                #Alex: Das Item kann hier raus, wenn das neue Trash Web läuft
                    my $forkSuffix = _WORKFLOWSUFFIX();
	            my $appTopic = $topic;
	            $appTopic =~ s/$forkSuffix$//g;
	            
	            my $appWeb = $web;
	            $appWeb =~ s/$forkSuffix$//g;
	            #Alex TrashTopic ausloten:             	           	
	            #Alex: Checken ob Topic schon einmal in den Müll verschoben wurde
                    my $trashTopic = $appWeb . $appTopic;
		    $trashTopic =~ s#/|\.##g; # remove subweb-deliminators
                    { # scope
                        my $numberedTrashTopic = $trashTopic;
	           	my $i = 1;
	            	while (Foswiki::Func::topicExists("Trash", $numberedTrashTopic)) {
                                $numberedTrashTopic = $trashTopic."_$i";
	            		$i++;
	            	}
                        $trashTopic = $numberedTrashTopic;
                    }
	            
	            # Hier Action 
#	            if ("VERWORFEN" eq $controlledTopic->getState()){	
                    if ($forkingAction && $forkingAction eq "DISCARD") {
                         $controlledTopic->purgeExtraNotify(); # XXX Wirklich?
                         my $origMeta = $controlledTopic->{meta};

                         # Move topic to trash
                         $controlledTopic->save(1);
                         Foswiki::Func::moveTopic( $web, $topic, "Trash", $trashTopic );

                         # Only unlock / add to history if appWeb exists (does not when topic)
                         if(Foswiki::Func::topicExists( $appWeb, $appTopic )) {
                             $url = Foswiki::Func::getScriptUrl( $appWeb, $appTopic, 'view' );

	            	     #Alex: Alte Metadaten wiederherstellen
	            	     my ($meta, $text) = Foswiki::Func::readTopic($appWeb, $appTopic);	
	            	 
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
	            	 
	            	     #Alex: Keine neue Revision erzeugen, Autor nicht überschreiben
	            	     Foswiki::Func::saveTopic( $appWeb, $appTopic, $meta, $text, { forcenewrevision => 0, minor => 1, dontlog => 1, ignorepermissions => 1 });
	            	 } else {
                             # if non-talk topic does not exist redirect to parent
                             my $parent = $origMeta->getParent();
                             my $parentWeb = $origMeta->web();
                             $url = Foswiki::Func::getViewUrl($parentWeb, $parent);
                         }
	            }
	            elsif ($forkingAction && $forkingAction eq "ACCEPT"){
                        # transfer ACLs from old document to new
                        transferACL($appWeb, $appTopic, $controlledTopic);
                        $controlledTopic->purgeExtraNotify();
			# increment MajorRev
			$controlledTopic->nextMajorRev();
                        # Will save changes after moving original topic away
	            	
	            	$url = Foswiki::Func::getScriptUrl( $appWeb, $appTopic, 'view' );
					            	
	            	#Alex: Force new Revision, damit Änderungen auf jeden Fall in der History sichtbar werden
	            	#try{
                        # only move topic if it has a talk suffix
                        if($appTopic eq $topic) {
	            	        $controlledTopic->save(1);
                        } else {
	            		#Zuerst kommt das alte Topic in den Müll, dann wird das neue verschoben

		            	Foswiki::Func::moveTopic( $appWeb, $appTopic, "Trash", $trashTopic);
				# Save now that I know i can move it afterwards
	            	        $controlledTopic->save(1);
		            	Foswiki::Func::moveTopic( $web, $topic, $appWeb, $appTopic );
                        }
	            	#Alex: Abfangroutine bei Fehlern muss hinzu
	            	#} catch Error::Simple with {
	            		#my $error = shift;
	            		#Foswiki::Func::moveTopic( "Trash", $trashTopic, $web, $appTopic);
	            	#}
	            }
	            else{
	            	$controlledTopic->save(1);
	            }
	            #Alex: Debug
	           
        		#Foswiki::Func::writeWarning( __PACKAGE__
	                #          . " State: $state" );
            #}

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
    my ($srcWeb, $srcTopic, $dst, $removeComments) = @_;

    my ($srcMeta, $srcText) = Foswiki::Func::readTopic($srcWeb, $srcTopic);
#    my ($dstMeta, $dstText) = Foswiki::Func::readTopic($dstWeb, $dstTopic);

    #gesperrte Seiten wieder entsperren
#    if (defined $meta->get("PREFERENCE", "ALLOWTOPICCHANGE")){
#        if ($meta->get("PREFERENCE", "ALLOWTOPICCHANGE")->{"value"} eq "nobody")
#            {
#                 $meta->remove("PREFERENCE", "ALLOWTOPICCHANGE");
#            }
#    }
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


    #Alex: Keine neue Revision erzeugen, Autor nicht überschreiben
#    Foswiki::Func::saveTopic( $dstWeb, $dstTopic, $dstMeta, $dstText, { forcenewrevision => 0, minor => 1, dontlog => 1, ignorepermissions => 1 });
}

# Removes all comments (from MetacommentPlugin)
sub removeComments {
     my ($controlledTopic) = @_;
     $controlledTopic->{meta}->remove("COMMENT");
}

# Mop up other WORKFLOW tags without individual handlers
sub commonTagsHandler {
    my ( $text, $topic, $web ) = @_;

    my $controlledTopic = _initTOPIC( $web, $topic );

    if ( $controlledTopic ) {

        # show all tags defined by the preferences
        my $url = Foswiki::Func::getScriptUrl( $web, $topic, 'view' );
        $controlledTopic->expandWorkflowPreferences( $url, $_[0] );

        return unless ( $controlledTopic->debugging() );
    }

    # Clean up unexpanded variables
    $_[0] =~ s/%WORKFLOW[A-Z_]*%//g;
}

sub _restFork {
    my ($session, $plugin, $verb, $response) = @_; 
    # Update the history in the template topic and the new topic
    my $query = Foswiki::Func::getCgiQuery();
    my $forkTopic = $query->param('topic');
    my @newnames = split(/,/, $query->param('newnames') || $forkTopic.(_WORKFLOWSUFFIX()));
#    my $newname = $query->param('newnames');
    my $lockdown = $query->param('lockdown');


    (my $forkWeb, $forkTopic) =
      Foswiki::Func::normalizeWebTopicName( undef, $forkTopic );
      
   
    if ( Foswiki::Func::topicExists( $forkWeb, $forkTopic ) ) {
        # Validated
        $forkWeb =
          Foswiki::Sandbox::untaintUnchecked( $forkWeb );
        $forkTopic =
          Foswiki::Sandbox::untaintUnchecked( $forkTopic );
    }


    my $controlledTopic = _initTOPIC( $forkWeb, $forkTopic );
    unless ($controlledTopic) {
        return "<span class='foswikiAlert'>WORKFLOWFORK: Topic nicht kontrolliert!</span>";
    }

    # this action will be done to the copied topic to bring it into a new state
    my $forkAction = $controlledTopic->getActionWithAttribute('FORK');
    unless ( $forkAction ) {
        return "<span class='foswikiAlert'>WORKFLOWFORK: No action can fork $forkTopic</span>";
    }

# This check is beeing done by getActionForFork
#	return unless $action
#	        && $state
#	          && $state eq $controlledTopic->getState()
#	            && $controlledTopic->haveNextState($action);

    my ($ttmeta, $tttext) = Foswiki::Func::readTopic(
        $forkWeb, $forkTopic);

    my $now = Foswiki::Func::formatTime( time(), undef, 'servertime' );
    my $who = Foswiki::Func::getWikiUserName();

    # Default to topicTALKSUFFIX if no newnames are given
    if ( scalar @newnames == 0 ) {
        my $forkSuffix = _WORKFLOWSUFFIX();
	@newnames = ($forkTopic.$forkSuffix);
    }

    my ($w, $t);

    foreach my $newname (@newnames) {    
        my $newForkTopic = Foswiki::Sandbox::untaintUnchecked( $newname );

        # create the new topic
        ($w, $t) =
            Foswiki::Func::normalizeWebTopicName( $forkWeb, $newForkTopic );
        
        next if (Foswiki::Func::topicExists($w, $t)); 
        
        #Alex: Topic mit allen Dateien kopieren
        my $handler = $session->{store}->getHandler( $forkWeb, $forkTopic );
        $handler->copyTopic($session->{store}, $w, $t);
        
        #Modac: Foswiki 1.0.9
        #$session->{store}->copyTopic($who, $forkWeb, $forkTopic, $w, $t);
        
        my $text = $tttext;
        my $meta = new Foswiki::Meta($session, $w, $t);
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
   
        # reset Auto-Mailinglist     
        $meta->putKeyed('WORKFLOWMAILINGLIST', 
            { name => 'WORKFLOWMAILINGLIST',
              PERMANENT => $controlledTopic->getExtraNotify('PERMANENT'),
              AUTO => ''
        });
        # mark as state change (althought it isn't) so it passes beforeSaveHandler
        local $isStateChange = 1; 
        Foswiki::Func::saveTopic($w, $t, $meta, $text,
            { forcenewrevision => 0, ignorepermissions => 1 });
        $isStateChange = 0;

        my $history = $ttmeta->get('WORKFLOWHISTORY') || {};
        $history->{value} .= "<br>Forked to " .
        "[[$w.$t]]" . " by $who at $now";
        $ttmeta->put( "WORKFLOWHISTORY", $history );

        if ($lockdown) {
            $ttmeta->putKeyed("PREFERENCE",
                { name => 'ALLOWTOPICCHANGE', value => 'nobody' });
        }
	
        # Modac: Save old Topic
        local $isStateChange = 1;
        Foswiki::Func::saveTopic( $forkWeb, $forkTopic, $ttmeta, $tttext,
                { forcenewrevision => 1, ignorepermissions => 1 });
    
        # Modell Aachen Settings:
        # Ueberfuehren in Underrevision:    
        my $newcontrolledTopic = _initTOPIC( $w, $t, undef, $meta, $text, 1);
        my $url;

        # I'll assume if it fails for one it fails for all newnames 
        unless ($newcontrolledTopic) {
            $url = Foswiki::Func::getScriptUrl(
                $w, $t, 'oops',
                template => "oopssaveerr",
                param1   => "Could not initialise workflow for "
                    . ( $w   || '' ) . '.'
                    . ( $t || '' )
                );
           Foswiki::Func::redirectCgiQuery( undef, $url );
           return "Error";
        }
 
        $newcontrolledTopic->changeState($forkAction);
        local $isStateChange = 1;
        $newcontrolledTopic->save(1);
    }

    #Redirect zum neuen Disskusions Topic
    return $response->redirect(Foswiki::Func::getViewUrl($w, $t));
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
        throw Foswiki::OopsException(
            'accessdenied',
            status => 403,
            def    => 'topic_access',
            web    => $_[2],
            topic  => $_[1],
            params => [
                'Edit topic',
'You are not permitted to edit this topic. You have been denied access by Q.Wiki'
            ]
        );
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
            $setField->{value}, $topic, $web, $meta);
        while($setField =~ m/"\s*([^"]+?)\s*=\s*([^"]*?)\s*"/g) {
          my $toSet = $1;
          my $value = $2;
	  $value =~ s#\$quot#"#g;
	  $value =~ s#\$dollar#\$#g;
          $meta->putKeyed('FIELD', { name => $toSet, title => $toSet, type => 'Set', value => $value } );
        }
      }
      # SetPref:
      if($setMeta) {
        $meta->remove('PREFERENCE', 'SetPref');
        $setMeta = Foswiki::Func::expandCommonVariables(
            $setMeta->{value}, $topic, $web, $meta);
        while($setMeta =~ m/"\s*([^"]+?)\s*=\s*([^"]*?)\s*"/g) {
          my $toSet = $1;
          my $value = $2;
	  $value =~ s#\$quot#"#g;
	  $value =~ s#\$dollar#\$#g;
          $meta->putKeyed('PREFERENCE', { name => $toSet, title => $toSet, type => 'Set', value => $value } );
        }
      }
      # RemoveMeta:
      if($removeMeta) {
        $meta->remove('PREFERENCE', 'RemoveMeta');
        my $removeList = Foswiki::Func::expandCommonVariables(
            $removeMeta->{value}, $topic, $web, $meta);
        my @toRemove = split(",", $removeList);
        foreach my $item (@toRemove) {
          $item =~ s#^\s*##;
          $item =~ s#\s*$##;
          $meta->remove($item);
        }
      }
      # RemovePref:
      if($removePref) {
        $meta->remove('PREFERENCE', 'RemoveMeta');
        my $removeList = Foswiki::Func::expandCommonVariables(
            $removeMeta->{value}, $topic, $web, $meta);
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

    # Otherwise we need to check if the packet of state change information
    # is present.
    my $changingState = 1;
    my %stateChangeInfo;
    foreach my $p ('WORKFLOWPENDINGACTION', 'WORKFLOWCURRENTSTATE',
                     'WORKFLOWPENDINGSTATE', 'WORKFLOWWORKFLOW') {
        $stateChangeInfo{$p} = $query->param($p);
        if (defined $stateChangeInfo{$p}) {
            $query->delete($p);
        } else {
            # All params must be present to change state
            $changingState = 0;
            last;
        }
    }

    my $controlledTopic;
    if ($changingState) {
        # See if we are expecting to apply a new state from query
        # params
        my ($wfw, $wft) = Foswiki::Func::normalizeWebTopicName(
            undef, $stateChangeInfo{WORKFLOWWORKFLOW} );

        # Can't use initTOPIC, because the data comes from the save
        my $workflow = new Foswiki::Plugins::KVPPlugin::Workflow(
            $wfw, $wft );
        $controlledTopic =
          new Foswiki::Plugins::KVPPlugin::ControlledTopic(
              $workflow, $web, $topic, $meta, $text );

    } else {
        # Otherwise we are *not* changing state so we can use initTOPIC
        $controlledTopic = _initTOPIC( $web, $topic, undef, $meta, $text, 1 );

    }

    return unless $controlledTopic;

    if ($changingState) {
        # The beforeSaveHandler has no way to abort the save,
        # so we have to do a state change without a topic save.
        $controlledTopic->changeState($stateChangeInfo{WORKFLOWPENDINGACTION});
        #
    } elsif ( !$controlledTopic->canEdit() ) {
        # Not a state change, make sure the AllowEdit in the state table
        # permits this action
        throw Foswiki::OopsException(
            'workflow',
            def   => 'topic_access',
            web   => $_[2],
            topic => $_[1],
            params =>
              [ 'Save topic',
'You are not permitted to save this topic. You have been denied access by Q.Wiki' ]
             );
    } else {
         my $newMeta = new Foswiki::Meta($Foswiki::Plugins::SESSION, $web, $topic, $text);
         my @newStateName = $newMeta->find('WORKFLOW');
        if(scalar @newStateName > 1) { # If 0 this is a new topic, or not controlled, or created without workflow
            throw Foswiki::OopsException(
                    'workflow',
                     def   => 'topic_access',
                     web   => $_[2],
                     topic => $_[1],
                     params =>
                         [ 'Save topic',
                     'Must find exactly one workflow in the topic, but found '.scalar(@newStateName).'!' ]
                );
        }
        # TODO Check if metacommentstuff changed unless workflow does so

        if( Foswiki::Func::topicExists( $web, $topic ) ) {
            # topic already exists, check if Workflowstuff didn't change
            # but do not touch uncontrolled topics
            if(scalar @newStateName == 0) {
                return;
            }
            
            my $oldMeta = $controlledTopic->{meta};
            my $oldState = $oldMeta->get( 'WORKFLOW' );
            unless($newStateName[0]->{name} eq $oldState->{name}) {
Foswiki::Func::writeWarning("Safe failed: States nicht gleich");#XXX Debug
                throw Foswiki::OopsException(
                    'workflow',
                     def   => 'topic_access',
                     web   => $_[2],
                     topic => $_[1],
                     params =>
                         [ 'Save topic',
                     'The Workflowstate '.$newStateName[0]->{name}.'does not match the old state '.$oldState->{name}.'! Topic can not be saved!' ]
                );
            }
# XXX Kommentare sind nicht schreibgeschützt
#remove klappt nicht, weils im text steht            $meta->remove('COMMENT');
#            foreach my $comment ($oldMeta->find( 'COMMENT' )) {
#                $meta->putKeyed('COMMENT', $comment);
#            }
        } else {
            # Make sure that newly created topics can't cheat with their state
            if(scalar @newStateName > 1) { # If 0 this is a new topic, or not controlled, if it's a copy it may be 1.
                throw Foswiki::OopsException(
                        'workflow',
                        def   => 'topic_access',
                        web   => $_[2],
                        topic => $_[1],
                        params =>
                            [ 'Save topic',
                        'Found an invalid workflow (there must be none in a newly created topic)!' ]
                );
            }
            # Assure that newly created topics have a state
#always overwrite?            unless ($mstate && $mstate->{ state }) {
                my $newAction = $controlledTopic->getActionWithAttribute('NEW');
                if($newAction) {
                    $controlledTopic->changeState($newAction);
                }
        }
    }

    # Append current user to the mailing list unless asked not to (ie. _changeMailingList)
    my $noappend = $query->param('NOAPPEND');
    unless($noappend && $noappend eq '1') {
        $controlledTopic->addExtraNotify(Foswiki::Func::getWikiUserName(), 'AUTO');
    }
    
}

sub indexTopicHandler {
  my ($indexer, $doc, $web, $topic, $meta, $text) = @_;

  # Modac : Mega Easy Implementation
  my $workflow = $meta->get('WORKFLOW');
  return unless $workflow;
  my $state = $workflow->{name};
  $doc->add_fields( process_state_s => $state) if $state;
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

