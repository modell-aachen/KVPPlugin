#
# Copyright (C) 2005 Thomas Hartkens <thomas@hartkens.de>
# Copyright (C) 2005 Thomas Weigert <thomas.weigert@motorola.com>
# Copyright (C) 2008 Crawford Currie http://c-dot.co.uk
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

#
# This object represents a workflow definition. It stores the preferences
# defined in the workflow topic, together with the state and transition
# tables defined therein.
#
package Foswiki::Plugins::KVPPlugin::ControlledTopic;

use strict;

use Foswiki (); # for regexes
use Foswiki::Func ();
use POSIX qw(strftime);

# Constructor
sub new {
    my ( $class, $workflow, $web, $topic, $meta ) = @_;

    my $forkSuffix = Foswiki::Plugins::KVPPlugin::_WORKFLOWSUFFIX();

    my $this = bless(
        {
            workflow  => $workflow,
            web       => $web,
            topic     => $topic,
            meta      => $meta,
            state     => $meta->get('WORKFLOW'),
            history   => $meta->get('WORKFLOWHISTORY'),
            forkweb   => $web,
            forktopic => $topic . $forkSuffix,
            isAllowing => {},
        },
        $class
    );

    # Ensure that controlled topics have a valid state
    unless($this->{state}) {
        $this->{state} = { name => $this->{workflow}->getDefaultState() };
        $this->{history} = {value=> ''};
    }

    # If old Format is present use that. Else default Revision to 0
    unless(defined $this->{state}->{Revision}) {
        my $wrev = $meta->get('WORKFLOWREV');
        if ($wrev) {
            $this->{state}->{Revision} = $wrev->{MajorRev};
            $meta->remove( 'WORKFLOWREV' );
        } else {
            $this->{state}->{Revision} = 0;
        }
    }

    return $this;
}

# Returns a hash with all the fields from the current state
sub getFields {
    my $this = shift;
    return $this->{workflow}->getFields($this->{state}->{name});
}

# Return true if debug is enabled in the workflow
sub debugging {
    my $this = shift;
    return $this->{workflow}->{preferences}->{WORKFLOWDEBUG};
}

# Return 'Set' preference defined in workflow topic.
sub getWorkflowPref {
    my ($this, $pref) = @_;
    return $this->{workflow}->{preferences}->{$pref};
}

# Get the current state of the workflow in this topic
sub getState {
    my $this = shift;
    return $this->{state}->{name};
}

# Get the available actions from the current state
sub getActions {
    my ($this) = @_;

    return ( [], [], [] ) unless $this->foswikiAllowsChange();

    return $this->{workflow}->getActions($this);
}

# Get attributes for the given action
sub getAttributes {
    my ($this, $action) = @_;
    my $attribs = $this->{workflow}->getAttributes($this->{state}->{name}, $action);
    return $this->expandMacros($attribs);
}

sub changedStateFromLastVersion {
    my ($this) = @_;

    my ( undef, undef, $version ) = $this->{meta}->getRevisionInfo();
    my $state = $this->getWorkflowMeta('name');
    my $lastTransitionVersion = $this->getWorkflowMeta("LASTVERSION_$state");
    return ($version-1) eq $lastTransitionVersion;
}

sub getTransitionInfos {
    my ($this) = @_;

    my %transition;
    my $action = $this->{state}->{"LASTACTION"};
    my $previousState = $this->{state}->{previousState};
    my $previousStateDisplayName = $this->{workflow}->getDisplayname($previousState, undef, 1),
    my $leavingStateUserId = $this->{state}->{"LEAVING_$previousState"};
    my $stateDisplayName = $this->getWorkflowMeta('displayname', undef, 1);
    my $remark = $this->{state}->{Remark};
    my $icon = $this->{workflow}->getTransitionCell($previousState,$action,"icon");
    my $attributes = $this->{workflow}->getTransitionCell($previousState,$action,"attribute");
    my $isCreation = $attributes =~ m/\bNEW\b/ ? 1 : 0;
    my $isFork = $attributes =~ m/\bFORK\b/ ? 1 : 0;
    my $lang = $Foswiki::Plugins::SESSION->i18n()->language();
    if($lang ne 'de') {
        $lang = 'en';
    }
    my $transitionText = $this->{workflow}->getTransitionCell($previousState,$action,"historytext$lang");
    my ( $revDate, $revUser, $version ) = $this->{meta}->getRevisionInfo();
    my $leavingStateUser = Foswiki::Func::expandCommonVariables("%RENDERUSER{\"$leavingStateUserId\" format=\"\$displayName\"}%");

    %transition = (
        state => $stateDisplayName,
        previousState => $previousStateDisplayName,
        leavingStateUser => $leavingStateUser,
        remark => $remark,
        time => strftime("%a, %d %b %Y %H:%M:%S %z", localtime($revDate)),
        icon => $icon,
        description => $transitionText,
        isCreation => $isCreation,
        isFork => $isFork,
        version => $version,
    );
    return \%transition;
}
sub getWorkflowMeta {
    my ( $this, $attributes, $languageOverwrite, $unescapeEntities ) = @_;

    # admittingly STATECHANGE and displayname would be more suitable under getWorkflowRow,
    # however they are usually called as if they were metadata.

    if($attributes eq 'STATECHANGE') {
        my $t = $this->{meta}->get( 'KVPSTATECHANGE', 'TRANSITION' );
        return unless $t && $t->{value};
        my ($old, $new) = ($t->{old}, $t->{new});
        my $oldDisplayName = $this->{workflow}->getDisplayname($old, $languageOverwrite);
        my $newDisplayName = $this->{workflow}->getDisplayname($new, $languageOverwrite);
        return "$oldDisplayName -> $newDisplayName";
    }

    if($attributes eq 'displayname') {
        return $this->{workflow}->getDisplayname($this->{state}->{name}, $languageOverwrite, $unescapeEntities);
    }

    return $this->{state}->{$attributes};
}

sub getWorkflowPreference {
    my ($this, $key) = @_;
    return $this->{workflow}->getPreference($key);
}

sub getDeniedFields {
    my ($this) = @_;
    my @columns = $this->{workflow}->getAllowFieldColumns($this->{state}->{name});
    my @denied = ();

    foreach my $column ( @columns ) {
        unless($this->{workflow}->_topicAllows($this, $column)) {
            my $fieldlc = $column =~ s#allowfield##r;
            my @fields = grep { lc($_) eq $fieldlc } @{$this->{workflow}->{allow_fields}};
            push @denied, @fields;
        }
    }
    return @denied;
}

# Remove LASTTIME_DRAFT etc. from META:WORKFLOW.
# Do save the topic afterwards.
# Parameters:
#    * $this: controlled topic
#    * state: Remove all data for this state. Leave empty to remove all of them.
sub clearWorkflowMeta {
    my ( $this, $state ) = @_;

    my $reg;
    if ( defined $state && $state !~ m#^\s*$#) {
        $reg = join('|', map { qr#_\Q$_\E(?:_DT)?$# } split( m#\s*,\s*#, $state ) );
    } else {
        $reg = qr#^(?:LASTPROCESSOR|LASTTIME|LASTVERSION|LEAVING)_#;
    }

    foreach my $key ( keys %{$this->{state}} ) {
        delete $this->{state}->{$key} if $key =~ m#$reg#;
    }

    # Replace workflow-metadata
    $this->{meta}->remove( 'WORKFLOW' ); # XXX sometime putKeyed doesn't replace
    $this->{meta}->putKeyed( "WORKFLOW", $this->{state} );
}

# Check if this transition needs more than one person's action to be performed
sub isProposableTransition {
    my ($this, $action) = @_;
    return $this->{workflow}->hasAttribute($this->{state}{name}, $action,
        'ALLOWEDPERCENT');
}

sub getTransitionProponents {
    my ($this, $action) = @_;
    my $state = $this->{state}{name};
    my $proponents = $this->{meta}->get('WORKFLOWPROPONENTS', "$state:$action");
    return unless $proponents;
    return grep /\S/, split(/\s*,\s*/, $proponents->{value});
}

# Clear proponents for all transitions available from the current state.
sub clearTransitionProponents {
    my ($this) = @_;
    my $state = $this->{state}{name};
    my @props = grep { $_->{name} =~ /^\Q$state:/ } $this->{meta}->find('WORKFLOWPROPONENTS');
    $this->{meta}->remove('WORKFLOWPROPONENTS', $_->{name}) foreach @props;
}

sub addTransitionProponent {
    my ($this, $action, $user) = @_;
    $user ||= $Foswiki::Plugins::SESSION->{user};
    my $state = $this->{state}{name};

    my $v = $this->{meta}->get('WORKFLOWPROPONENTS', "$state:$action");
    $v = ref($v) ? $v->{value} : '';
    $v = [split(/\s*,\s*/, $v)];
    my %props;
    @props{@$v} = @$v;
    $props{$user} = 1;
    $this->{meta}->putKeyed('WORKFLOWPROPONENTS', {
        name => "$state:$action",
        value => join(', ', keys %props),
    });
}

# Check if a user can still sign as a proponent for a transaction
# (i.e. none of the 'allowed' entries that can be fulfilled by the user
# have been signed for yet)
sub isPotentialProponent {
    my ($this, $action, $user) = @_;
    return 1 unless $this->isProposableTransition($action);

    my $attr = $this->getAttributes($action);
    $user ||= $Foswiki::Plugins::SESSION->{user};
    my $p2a = $this->mapProponentsToAllowed($action);

    while (my ($allowed, $signer) = each(%$p2a)) {
        next if defined $signer;

        my $cuid = Foswiki::Func::getCanonicalUserID($allowed);
        return 1 if defined $cuid && $cuid eq $user;
        next unless Foswiki::Func::isGroup($allowed);
        my $it = Foswiki::Func::eachGroupMember($allowed);
        while ($it->hasNext) {
            my $candidate = Foswiki::Func::getCanonicalUserID($it->next);
            return 1 if $candidate eq $user;
        }
    }
    return 0;
}

# Given a list of proponents (by way of current state and desired action),
# find out which entries from the allowed list each of them represents
sub mapProponentsToAllowed {
    my ($this, $action) = @_;
    my @props = $this->getTransitionProponents($action);
    my $allowed = $this->{workflow}->getTransitionCell($this->{state}{name}, $action, 'allowed');
    return {} unless defined $allowed;

    $allowed = $this->expandMacros($allowed);
    $allowed =~ s#^\s+##;
    $allowed =~ s#\s+$##;

    my @allowed = grep /\S/, split(/\s*,\s*/, $allowed);
    my $map = {};
    for my $a (@allowed) {
        my $user = Foswiki::Func::getCanonicalUserID($a);
        $map->{$a} = undef;
        if (defined $user) {
            if (grep /^\Q$user\E$/, @props) {
                $map->{$a} = $user;
                next;
            }
        }
        next unless Foswiki::Func::isGroup($a);
        my $it = Foswiki::Func::eachGroupMember($a);
        while ($it->hasNext) {
            my $candidate = Foswiki::Func::getCanonicalUserID($it->next);
            if (grep /^\Q$candidate\E$/, @props) {
                $map->{$a} = $candidate;
                next;
            }
        }
    }
    $map;
}

# Alex: Get the extra Mailinglist (People involved in the Discussion)
sub getContributors {
    my ($this, $state) = @_;

    $state ||= $this->{state}->{name};

    my $contributors = $this->{meta}->get( 'WRKFLWCONTRIBUTORS', $state);
    return '' unless $contributors;

    return $contributors->{value};
}

# Add another user to the Mailinglist
sub addContributors {
    my ( $this, $extraname, $state ) = @_;

    $extraname =~ s/^\s*//;
    $extraname =~ s/\s*$//;
    return unless $extraname;

    $state ||= $this->{state}->{name};

    my $old = $this->{meta}->get( 'WRKFLWCONTRIBUTORS', $state);
    my $contributorlist;

    if($old) {
        $contributorlist = $old->{value};
        return if $contributorlist =~ /\b$extraname\b/;
        $contributorlist = "$contributorlist,$extraname";
    } else {
        $contributorlist = $extraname;
    }
    # assign
    $this->{meta}->putKeyed( 'WRKFLWCONTRIBUTORS', {name => $state, value => $contributorlist } );
}

sub purgeContributors {
    my ( $this ) = @_;
    $this->{meta}->remove( 'WRKFLWCONTRIBUTORS' );
}

# Will increase the WorkflowRev
sub nextRev {
    my ( $this ) = @_;
    $this->{state}->{Revision}++;
}

# Sets the WorkflowRev
sub setRev {
    my ( $this, $rev ) = @_;
    $this->{state}->{Revision} = $rev;
}

# Set the current state in the topic
# Alex: Bearbeiter hinzu
sub setState {
    my ( $this, $state, $version, $remark, $action ) = @_;
    my $oldState = $this->{state}->{name};
    $this->{state}->{name} = $state;
    $this->{state}->{previousState} = $oldState;

    $this->{state}->{"LASTVERSION_$state"} = $version;
    $this->{state}->{"LASTPROCESSOR_$state"} = Foswiki::Func::getCanonicalUserID();
    $this->{state}->{"LEAVING_$oldState"} = Foswiki::Func::getCanonicalUserID() if($oldState);
    $this->{state}->{"LASTTIME_$state"} =
      Foswiki::Time::formatTime( time(), '$day.$mo.$year', 'servertime' );
    $this->{state}->{"LASTTIME_${state}_DT"} = time();
    $this->{state}->{"LASTACTION"} = $action || '';

    $this->{state}->{Remark} = $remark || '';

    # Replace workflow-metadata
    $this->{meta}->remove( 'WORKFLOW' ); # XXX sometime putKeyed doesn't replace
    $this->{meta}->putKeyed( "WORKFLOW", $this->{state} );

    # Leave state-change comment
    $this->{meta}->remove( 'KVPSTATECHANGE' );
    $this->{meta}->putKeyed( 'KVPSTATECHANGE', {name => 'TRANSITION', value=> "$oldState -> $state", old=>$oldState, new=>$state} );

    # manage comments
    if( $Foswiki::cfg{Extensions}{KVPPlugin}{DoNotManageMetaCommentACLs} ) {
        if( $Foswiki::cfg{Extensions}{KVPPlugin}{ScrubMetaCommentACLs} ) {
            $this->{meta}->remove( 'PREFERENCE', 'ALLOWTOPICCOMMENT' );
            $this->{meta}->remove( 'PREFERENCE', 'DENYTOPICCOMMENT' );
            $this->{meta}->remove( 'PREFERENCE', 'DISPLAYCOMMENTS' );
        }
    } else {
        my $allowComment = $this->{workflow}->getRow($this->getState(), 'allowcomment');
        $allowComment = $this->expandMacros( $allowComment );
        if($allowComment) {
            $this->{meta}->putKeyed("PREFERENCE",
                { name => 'DISPLAYCOMMENTS', value => 'on' }
            );
            if($allowComment =~ m/\bLOGGEDIN\b/) {
                my $wikiguest = $Foswiki::cfg{DefaultUserWikiName};
                $this->{meta}->putKeyed("PREFERENCE",
                    {
                        name => 'DENYTOPICCOMMENT',
                        title => 'DENYTOPICCOMMENT',
                        value => ($allowComment =~ m/\b$wikiguest\b/)?'nobody':$wikiguest
                    }
                );
                $this->{meta}->remove( 'PREFERENCE', 'ALLOWTOPICCOMMENT' );
            } else {
              $this->{meta}->remove( 'PREFERENCE', 'DENYTOPICCOMMENT' );
              $this->{meta}->putKeyed("PREFERENCE",
                    { name => 'ALLOWTOPICCOMMENT', value => $allowComment }
              );
            }
        } else {
            $this->{meta}->putKeyed("PREFERENCE",
                { name => 'DISPLAYCOMMENTS', value => 'off' }
            );
        }
    }
}

# Get the history string for the topic
sub getHistoryText {
    my $this = shift;

    return '' unless $this->{history};
    return $this->{history}->{value} || '';
}

# Return true if a new state is available using this action
sub haveNextState {
    my ( $this, $action ) = @_;

    return 0 unless $this->foswikiAllowsChange();

    return $this->{workflow}->getNextState( $this, $action );
}

sub foswikiAllowsChange {
    my $this = shift;

    unless (defined $this->{foswikiAllowsChange}) {
        $this->{foswikiAllowsChange} = Foswiki::Func::checkAccessPermission(
            'CHANGE', $Foswiki::Plugins::SESSION->{user},
            $this->{meta}->text(), $this->{topic}, $this->{web},
            $this->{meta}
        );
    }
    return $this->{foswikiAllowsChange};
}

# Some day we may handle the can... functions indepedently. For now,
# they all check editability thus....
sub isModifyable {
    my $this = shift;

    # See if the workflow allows an edit
    unless (defined $this->{isEditable}) {
        $this->{isEditable} = (
            # Does the workflow permit editing?
            $this->{workflow}->allowEdit($this)
            # Does Foswiki permit editing?
            && $this->foswikiAllowsChange()
        ) ? 1 : 0;
    }
    return $this->{isEditable};
}

# Get (first) action that leads to a fork
sub getActionWithAttribute {
    my ( $this, $attribute ) = @_;

    return [ '', '' ] unless $this->foswikiAllowsChange();

    return $this->{workflow}->getActionWithAttribute($this, $attribute);
}

# Indicates if all comments will be removed if this action is executed on the state
sub isRemovingComments {
    my ( $this, $state, $action ) = @_;
    return $this->{workflow}->hasAttribute($state, $action, 'FORCEDELETECOMMENTS');
}

sub getTransitionAttributesArray {
    my ( $this, $displayname ) = @_;

    return $this->{workflow}->getTransitionAttributesArray($this, 0, $displayname );
}

sub getTransitionAttributes {
    my ( $this ) = @_;

    my $currentState = $this->{state}{name};
    my ($allow, $suggest, $comment) = $this->{workflow}->getTransitionAttributes($currentState);
    my @unsatisfiedMandatoryFields = Foswiki::Plugins::KVPPlugin::Workflow::getUnsatisfiedMandatoryFields($this);
    my $unsatisfiedMandatory = ',';
    my $alreadyProposed = ',';

    for my $t (@{$this->{workflow}->getTransitions($currentState)}) {
        unless($t->{attribute} && $t->{attribute} =~ m#\bIGNOREMANDATORY\b#) {
            $unsatisfiedMandatory .= $t->{action} . ',';
        }
        next if $this->isPotentialProponent($t->{action});
        $alreadyProposed .= "$t->{action},";
    }
    return ($allow, $suggest, $comment, $alreadyProposed, $unsatisfiedMandatory, \@unsatisfiedMandatoryFields);
}

# Check if the topic is allowed to fork
# Returns the first allowed action.
sub isForkable {
    my $this = shift;

    unless (defined $this->{isAllowingFork}) {
        $this->{isAllowingFork} = $this->getActionWithAttribute('FORK');
    }
    return $this->{isAllowingFork};
}

# Returns true if the workflow allows the action.
# Does NOT check topic permissions.
sub isAllowing {
    my ($this, $action) = @_;

    unless (defined $this->{isAllowing}{$action}) {
        $this->{isAllowing}{$action} = $this->{workflow}->_topicAllows($this, $action);
    }
    return $this->{isAllowing}{$action};
}

# Return true if this topic is movable
sub canMove {
    my $this = shift;

    # See if the workflow allows a move
    unless (defined $this->{isMovable}) {
        $this->{isMovable} = (
            # Does the workflow permit moving?
            $this->{workflow}->allowMove($this)
            # Does Foswiki permit moving?
            && Foswiki::Func::checkAccessPermission(
                'RENAME', $Foswiki::Plugins::SESSION->{user},
                $this->{meta}->text(), $this->{topic}, $this->{web},
                $this->{meta})
        ) ? 1 : 0;
    }
    return $this->{isMovable};
}

# Return true if this topic is editable
sub canEdit {
    my $this = shift;
    return $this->isModifyable();
}

# Return true if this topic is attachable to
sub canAttach {
    my $this = shift;
    return $this->isModifyable();
}

# Return true if this topic is forkable
sub canFork {
    my $this = shift;
    return $this->isForkable();
}

# Get the contents of the given row for the current topic in it's current state
sub getRow {
    my ($this, $row, $unescapeEntities) = @_;
    return $this->{workflow}->getRow($this->getState(), $row, $unescapeEntities);
}

# Get task attached to topic
sub getTask {
    my ($this) = @_;

    return $this->{workflow}->getTask($this->{state}->{name});
}

# Returns array of people assigned to currently attached task
sub getTaskedPeople {
    my ( $this ) = @_;

    my $taskname = $this->{state}->{TASK};
    return undef unless $taskname;
    my $task = $this->{workflow}->getTask( $taskname );
    return undef unless $task;
    return _listToWikiNames( $this->expandMacros( $task->{who} ) );
}

# change the state of the topic. Does *not* save the updated topic.
# Returns a notify-mail of the change to listeners.
sub changeState {
    my ( $this, $action, $remark ) = @_;
    my $oldstate = $this->{state}->{name};

    my $state = $this->{workflow}->getNextState( $this, $action );
    unless ($state) {
        $action ||= '';
        Foswiki::Func::writeWarning("changeState: No NextState! Action=".$action." currentState=".$this->{state}->{name});
        return;
    }
    #Alex: Es muss garantiert sein, dass die Form nicht leer ist (also " ")
    my $notify = $this->{workflow}->getNotifyList( $this, $action );
    my $attributes = $this->{workflow}->getAttributes( $this->getState(), $action );

    my ( $revdate, $revuser, $version ) = $this->{meta}->getRevisionInfo();
    if (ref($revdate) eq 'HASH') {
        my $info = $revdate;
        ( $revdate, $revuser, $version ) =
          ( $info->{date}, $info->{author}, $info->{version} );
    }

    # remember task
    { # Scope
        my $taskname = $this->{workflow}->getTaskForAction( $this, $action );
        $this->{state}->{'TASK'} = $taskname;
        my $duedate = '';
        if($taskname) {
            my $task = $this->{workflow}->getTask($taskname);
            if($task) {
                my $duration = $task->{when};
                if($duration) {
                    $duration *= 24*60*60; # to epoch
                    $duedate =
                      Foswiki::Time::formatTime( time() + $duration, '$day.$mo.$year', 'servertime' );
                }
            }
        }
        $this->{state}->{"TASK_DUE"} = $duedate;
    }

    $this->setState($state, $version, $remark, $action);

    my $fmt = Foswiki::Func::getPreferencesValue("WORKFLOWHISTORYFORMAT")
      || '<br />$state -- $date';
    $fmt =~ s/\$wikiusername/Foswiki::Func::getWikiUserName()/geo;
    $fmt =~ s/\$state/$this->getState()/goe;
    $fmt =~ s/\$date/$this->{state}->{"LASTTIME_$state"}/geo;
    $fmt =~ s/\$rev/$this->{state}->{"LASTVERSION_$state"}/geo;
    $fmt =~ s/\$expand\((.*?)(?<!\\)\)/$this->expandHistory($1)/geo;
    if ( defined &Foswiki::Func::decodeFormatTokens ) {
        # Compatibility note: also expands $percnt etc.
        $fmt = Foswiki::Func::decodeFormatTokens($fmt);
    }
    else {
        my $mixedAlpha = $Foswiki::regex{mixedAlpha};
        $fmt =~ s/\$quot/\"/go;
        $fmt =~ s/\$n/\n/go;
        $fmt =~ s/\$n\(\)/\n/go;
        $fmt =~ s/\$n([^$mixedAlpha]|$)/\n$1/gos;
    }

    $this->{history}->{value} .= $fmt;
    $this->{meta}->put( "WORKFLOWHISTORY", $this->{history} );

    # Set preferences / fields from transition-table
    if ($attributes) {
        my $s = $this->getState();
        while ( $attributes =~ m/SETPREF\(\s*(\w+)\s*=\s*"([^"]*)"\s*\)/g ) {
            my $name = $1;
            my $value = Foswiki::Func::decodeFormatTokens( $2 || '' );
            $value = Foswiki::Func::expandCommonVariables( $value, $this->{topic}, $this->{web}, $this->{meta} );
            $this->{meta}->remove( 'PREFERENCE', $name );
            $this->{meta}->putKeyed( 'PREFERENCE', { name=>$name, value=>$value, type=>'Set' } );
            Foswiki::Func::setPreferencesValue( $name, $value ); # in case its important for the mail
        }
        while ( $attributes =~ m/REMOVEPREF\(\s*"([^"]*)"\s*\)/g ) {
            my $name = $1;
            $name = Foswiki::Func::expandCommonVariables( $name, $this->{topic}, $this->{web}, $this->{meta} );
            if($name) {
                $this->{meta}->remove( 'PREFERENCE', $name);
                Foswiki::Func::setPreferencesValue( $name, '' ); # in case its important for the mail
            }
        }
        while ( $attributes =~ m/SETFORM\(\s*(\w+)\s*\)/g ) {
            my $value = Foswiki::Func::decodeFormatTokens( $1 || '' );
            $value = Foswiki::Func::expandCommonVariables( $value, $this->{topic}, $this->{web}, $this->{meta} );
            $this->{meta}->remove( 'FORM' );
            $this->{meta}->put( 'FORM', { name=>$value } ) if $value && $value ne '';
        }
        while ( $attributes =~ m/SETFIELD\(\s*(\w+)\s*=\s*"([^"]*)"\s*\)/g ) {
            my $name = $1;
            my $value = Foswiki::Func::decodeFormatTokens( $2 || '' );
            $value = Foswiki::Func::expandCommonVariables( $value, $this->{topic}, $this->{web}, $this->{meta} );
            $this->{meta}->putKeyed( 'FIELD', { name=>$name, title=>$name, value=>$value } );
        }
        if ( $attributes =~ m/FORCESAVECONTEXT/ ) {
            $this->{forceSaveContext} = 1;
        }
    }

    $this->clearTransitionProponents;

    my $formColumn = $this->getRow('form');
    if(defined $formColumn && $formColumn ne '') {
        $this->{meta}->remove('FORM');
        $this->{meta}->put('FORM', { name => $formColumn });
    }

    my $notification;
    # generate mails
    if ($notify) {
        # Expand vars in the notify list. This supports picking up the
        # value of the notifees from the topic itself.
        $notify = $this->expandMacros($notify);

        my $language = Foswiki::Func::getPreferencesValue('MAIL_LANGUAGE') || $Foswiki::cfg{Extensions}{KVPPlugin}{MailLanguage} || $Foswiki::Plugins::SESSION->i18n()->language();
        $language = Foswiki::Func::expandCommonVariables($language) if $language;

        $notification = {
            template => 'mailworkflowtransition',
            options => { IncludeCurrentUser => 0, AllowMailsWithoutUser => 1, webtopic => "$this->{web}.$this->{topic}" },
            settings => { TARGET_STATE => $this->getState(), TARGET_STATE_DISPLAY => $this->getWorkflowMeta('displayname', $language, 1) =~ s#%#<nop>%<nop>#gr, EMAILTO => $notify, LANGUAGE => $language },
            extra => { action => $action, ncolumn => $notify },
        };
    } else {
        Foswiki::Func::writeWarning("Topic: '$this->{web}.$this->{topic}' Transition: '$action' Notify column: empty") if ($Foswiki::cfg{Extensions}{KVPPlugin}{MonitorMails});
    }

    return $notification;
}

# Move the controlled topic and update internal state
sub moveTopic {
    my ( $this, $newWeb, $newTopic) = @_;

    Foswiki::Func::moveTopic( $this->{web}, $this->{topic}, $newWeb, $newTopic );
    $this->{web} = $newWeb;
    $this->{topic} = $newTopic;
}

sub expandHistory {
    my ( $this, $text ) = @_;

    $text = $this->expandMacros($text);
    $text =~ s#\\\)#)#g;
    return $text;
}

# Save the topic to the store
sub save {
    my $this = shift;
    my $ignore = shift;

    my $options;
    if($ignore == 1) {
        $options = { forcenewrevision => 1, ignorepermissions => 1 };
    } else {
        $options = { forcenewrevision => 1};
    }
    my $saveContextActive = 1;
    my $session = $Foswiki::Plugins::SESSION;
    if ($this->{forceSaveContext} && !$session->inContext('save')) {
        $saveContextActive = 0;
        $session->enterContext('save', 1);
        Foswiki::Func::pushTopicContext($this->{web}, $this->{topic});
    }
    Foswiki::Func::saveTopic(
        $this->{web}, $this->{topic}, $this->{meta},
        $this->{meta}->text(), $options
    );
    unless ($saveContextActive) {
        $session->leaveContext('save');
        Foswiki::Func::popTopicContext();
    }
}

# Alex: Alle doppelten Werte aus einem Array lschen
sub del_double {
    my %all=();
    @all{@_}=1;
    delete $all{''};
    return (keys %all);
}

sub expandMacros {
    my ( $this, $text ) = @_;
    my $c = Foswiki::Func::getContext();

    # Workaround for Item1071
    my $memory = $c->{can_render_meta};
    $c->{can_render_meta} = $this->{meta};
    my $session = $Foswiki::Plugins::SESSION; # do not use $meta->session(), as this is what pushTopicContext uses
    my $sameTopicContext = $this->{web} eq $session->{webName} && $this->{topic} eq $session->{topicName};
    Foswiki::Func::pushTopicContext($this->{web}, $this->{topic}) unless $sameTopicContext;
    $text = Foswiki::Func::expandCommonVariables( $text, $this->{topic}, $this->{web}, $this->{meta} );
    Foswiki::Func::popTopicContext() unless $sameTopicContext;
    $c->{can_render_meta} = $memory;
    return $text;
}

# Returns the web.topic of the workflow controlling this topic.
sub getWorkflowName {
    my ( $this ) = @_;

    return $this->{workflow}->getName();
}

sub _listToWikiNames {
    my ( $string ) = @_;
    $string =~ s#^\s*|\s*$##g;
    my @persons = ();
    # Alex: Get Users from Groups
    foreach my $group ( split(/\s*,\s*/, $string) ) {
        next unless $group;
        if ( Foswiki::Func::isGroup($group)) {
            my $it = Foswiki::Func::eachGroupMember($group);
            while ($it->hasNext()) {
                my $user = Foswiki::Func::getWikiName( $it->next() );
                push( @persons, $user);
            }
        }
        # Alex: Handler fr Nicht-Gruppen
        else {
            my $user = Foswiki::Func::getWikiName( $group );
            push( @persons, $user);
        }
    }
    return \@persons;
}

1;
