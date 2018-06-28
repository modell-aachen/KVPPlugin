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
package Foswiki::Plugins::KVPPlugin::Workflow;

use strict;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Plugins::ModacHelpersPlugin ();

sub new {
    my ( $class, $web, $topic ) = @_;

    if (defined &Foswiki::Sandbox::untaint) {
        $web = Foswiki::Sandbox::untaint(
            $web, \&Foswiki::Sandbox::validateWebName
        );
        $topic = Foswiki::Sandbox::untaint(
            $topic, \&Foswiki::Sandbox::validateTopicName
        );
    }

    return undef unless ($web && $topic);

    my ( $meta, $text ) = Foswiki::Func::readTopic( $web, $topic );
    unless (
            Foswiki::Func::checkAccessPermission(
                'VIEW', $Foswiki::Plugins::SESSION->{user},
                $text, $topic, $web, $meta
            )
        )
    {
        return undef;
    }
    my $this = bless(
        {
            name               => "$web.$topic",
            preferences        => {},
            states             => {},
            allow_fields       => undef,
            transitions        => [],
            transitions_state  => {}, # Lookup transitions by source state
            transitions_action => {}, # Look transitions by tuple source state / action
            tasks              => [],
            meta               => $meta
        },
        $class
    );
    my $inTable;
    my @fields;
    my $defaultCol;
    my %default = ();
    my @defaultfields;

    # Yet another table parser
    # Default table:
    # | *State Type*  |
    # State table:
    # | *State*       | *Allow Edit* | *Message* |
    # Transition table:
    # | *State* | *Action* | *Next state* | *Allowed* |
    # Task table:
    # | *Task* | *Who* | *Description* | *Time* |
    foreach my $line ( split( /\n/, $text ) ) {
        if (
            $line =~ s/^\s*\|([\s*]*State[\s*]*\|
                           [\s*]*Action[\s*]*\|.*)\|\s*$/$1/ix
          )
        {

            # Transition table header
            @fields = map { _cleanField($_) } split( /\s*\|\s*/, $line );

            $inTable = 'TRANSITION';
        }
        elsif (
            $line =~ s/^\s*\|([\s*]*State[\s*]*\|
                              [\s*]*Allow\s*Edit[\s*]*\|.*)\|\s*$/$1/ix
          )
        {

            # State table header
            @fields = map { _cleanField($_) } split( /\s*\|\s*/, $line );

            # remember original 'allow field ...' columns
            my @allowfields = map { $_ =~ s#^\s*##; $_ =~ s#\s*$##; $_ =~ s#\*##g; $_ =~ s#^allow\s+field\s*##i; $_ } grep { $_ =~ m#^\s*\*?allow\s+field\s*#i } split(/\|/, $line );
            $this->{allow_fields} = \@allowfields;

            $inTable = 'STATE';
        }
        elsif ( $line =~ /^(?:\t|   )+\*\sSet\s(\w+)\s=\s*(.*)$/ ) {
            # store preferences
            $this->{preferences}->{$1} = $2;
        }
        elsif (
            $line =~ s/^\s*\|([\s*]*State\s*Type[\s*]*\|.*)\|\s*$/$1/ix
        )
        {
            $inTable = 'DEFAULT';
            $defaultCol = 'statetype'; # XXX
            @defaultfields = map { _cleanField($_) } split( /\s*\|\s*/, $line );
        }
        elsif (
            $line =~ s/^\s*\|([\s*]*Task[\s*]*\|.*)\|\s*$/$1/ix
        )
        {
            $inTable = 'TASK';
            @fields = map { _cleanField($_) } split( /\s*\|\s*/, $line );
        }
        elsif ( defined($inTable) && $line =~ s/^\s*\|\s*(.*?)\s*\|\s*$/$1/ ) {

            my %data;
            my $i = 0;
            if ( $inTable eq 'DEFAULT' ) {
                foreach my $col ( split( /\s*\|\s*/, $line ) ) {
                    $data{ $defaultfields[ $i++ ] } = $col;
                }

                $default{ $data{ $defaultCol } } = \%data;
            } else {
                foreach my $col ( split( /\s*\|\s*/, $line ) ) {
                    $data{ $fields[ $i++ ] } = $col;
                }

                if ( $inTable eq 'TRANSITION' ) {
                    push( @{ $this->{transitions} }, \%data );
                    $this->{transitions_action}{"$data{state}:$data{action}"} = \%data;
                    push @{ $this->{transitions_state}{ $data{state} } }, \%data;
                }
                elsif ( $inTable eq 'STATE' ) {

                    # read row in STATE table
                    $this->{defaultState} ||= $data{state};
                    $this->{states}->{ $data{state} } = \%data;

                    # Insert default values
                    if ( $defaultCol ) {
                        my $defaultKey = $data{ $defaultCol };
                        if ($defaultKey) {
                            my $defaultRow = $default{ $defaultKey };
                            if( $defaultRow ) {
                                foreach my $def (keys %$defaultRow){
                                    $data{ $def } = $defaultRow->{ $def } unless $data { $def };
                                }
                            }
                        }
                    }
                }
                elsif ( $inTable eq 'TASK' ) {
                    push( @{ $this->{tasks} }, \%data );
                }
            }
        }
        else {
            undef $inTable;
        }
    }
    unless($this->{defaultState}) {
        Foswiki::Func::writeWarning("Invalid state table in $web.$topic");
        Foswiki::Plugins::KVPPlugin::_broadcast( '%MAKETEXT{"Invalid state table in [_1]" args="'.$web.'.'.$topic.'"}%' );
        return undef;
    }

    return $this;
}

sub getDisplayTabs {
    my ($this) = @_;
    my @tabs = ();   
    foreach my $state (keys %{$this->{states}}) {
        next unless $this->{states}{$state}->{displayedtab} && !grep{$_ =~ m#$this->{states}{$state}->{displayedtab}#} @tabs;
        push(@tabs, $this->{states}{$state}->{displayedtab});
    }
    return sort @tabs;
}

sub getAllowFieldColumns {
    my ($this, $state) = @_;

    my $stateTable = $this->{states}->{$state};

    return grep { $_ =~ m#^allowfield# } keys %$stateTable;
}

sub getPreference {
    my ($this, $key) = @_;
    return $this->{meta}->getPreference($key);
}

# All transitions that can follow a given state
sub getTransitions {
    my ($this, $state) = @_;
    return $this->{transitions_state}{$state} || [];
}

# Transition for a specific state/action tuple
sub getTransition {
    my ($this, $state, $action) = @_;
    return $this->{transitions_action}{"$state:$action"};
}

# Returns a single cell from a transition given state/action/column
# Returns undef if the transition or column doesn't exist
sub getTransitionCell {
    my ($this, $state, $action, $col) = @_;
    my $t = $this->getTransition($state, $action);
    return unless $t;
    return $t->{$col};
}

# Get the possible actions with warnings associated with the given state
# Will not deliver actions with NEW, FORK or HIDDEN
sub getActions {
    my ( $this, $topic) = @_;
    my @actions      = ();
    my @warnings     = ();
    my $currentState = $topic->getState();
    foreach my $row ( @{ $this->getTransitions($currentState) } ) {
        my $attribute = $row->{attribute} || '';
        if (
                $attribute !~ /\b(?:FORK|NEW|HIDDEN)\b/
                && _isAllowed($topic->expandMacros( $row->{allowed} ))
                && _isTrue($topic->expandMacros( $row->{condition} ))
                && $topic->expandMacros( $row->{nextstate} )
            )
        {
            push( @actions, $row->{action} );
            push( @warnings, $row->{warning} );
        }
    }
    return (\@actions, \@warnings);
}

# Get first allowed action for this state that has this attribute set in the 'Attribute' column
sub getActionWithAttribute {
    my ( $this, $topic, $attribute ) = @_;
    my $currentState = $topic->getState();
    if ( $attribute eq 'FORK' ) {
        my $suffix = Foswiki::Plugins::KVPPlugin->_WORKFLOWSUFFIX();
        return [ '', '' ] if ( $topic->{topic} =~ m/$suffix$/ ); # forking this would create a ...TalkTalk
    }
    foreach my $t( @{ $this->getTransitions($currentState) } ) {
        if ( $t->{attribute} && $t->{attribute} =~ /(?:^|\W)$attribute(?:\W|$)/ ) {
            my $allowed = $topic->expandMacros( $t->{allowed} );
            if ( _isAllowed($allowed) && _isTrue($topic->expandMacros($t->{condition})) ) {
                return [ $t->{action}, $t->{warning} ];
            }
        }
    }
    return [ '', '' ];
}

# Returns the attributes of the given action for the given state
sub getAttributes {
    my ( $this, $currentState, $action ) = @_;
    return $this->getTransitionCell($currentState, $action, 'attribute') || '';
}

# Indicates if a given attribute is set in the 'Attribute' column
# return '1' if set, '0' otherwise.
sub hasAttribute {
    my ( $this, $state, $action, $attribute ) = @_;
    my $attr = $this->getAttributes($state, $action);
    return ( $attr && $attr =~ /(?:\W|^)$attribute(?:\W|$)/ );
}

sub getTransitionAttributesArray {
    my ( $this, $topic, $noChecks ) = @_;

    my $state = $topic->getState();

    return [] unless $state && $topic->foswikiAllowsChange(); # No state happens when topic has no META:WORKFLOW...

    my @transitions = ();

    my @missingMandatory = map{ $_->{mapped_title} } Foswiki::Plugins::ModacHelpersPlugin::getNonSatisfiedFormFields($topic->{meta});
    my $mandatorySatisfied = 0 == scalar @missingMandatory;

    foreach my $transition ( @{ $this->getTransitions($state) } ) {
        unless($noChecks) {
            next if $transition->{attribute} && $transition->{attribute} =~ m/\b(?:FORK|NEW|HIDDEN)\b/;
            next unless (
                _isAllowed($topic->expandMacros( $transition->{allowed} ))
                && _isTrue($topic->expandMacros( $transition->{condition} ))
                && $topic->expandMacros( $transition->{nextstate} )
            );
        }
        my ($allow, $suggest, $comment, $mandatoryNotSatisfied);
        if($transition->{attribute}) {
            if( $transition->{attribute} =~ /(?:\W|^)ALLOWDELETECOMMENTS(?:\W|$)/ ) {
                $allow = 1;
            }
            if( $transition->{attribute} =~ /(?:\W|^)SUGGESTDELETECOMMENTS(?:\W|$)/ ) {
                $suggest = 1;
            }
            if( $transition->{attribute} =~ /(?:\W|^)REMARK(?:\W|$)/ ) {
                $comment = 1;
            }
        }
        unless($mandatorySatisfied || ($transition->{attribute} && $transition->{attribute} =~ m#\bIGNOREMANDATORY\b#)) {
            $mandatoryNotSatisfied = \@missingMandatory;
        }
        push @transitions, {
            action => $transition->{action},
            warning => $transition->{warning},
            allow_delete_comments => $allow,
            suggest_delete_comments => $suggest,
            remark => $comment,
            proponent => $topic->isPotentialProponent($transition->{action}),
            mandatoryNotSatisfied => $mandatoryNotSatisfied,
        };
    }

    return \@transitions;
}

# This returns lists for a JavaScript with all actions that:
# * allow deleting comments
# * suggest deleting comments
# * have remarks
# Both lists will start and end with a ',' to make searches easier.
sub getTransitionAttributes {
    my ( $this, $state ) = @_;

    my $allow = ',';
    my $suggest = ',';
    my $comment = ',';

    return ($allow, $suggest, $comment) unless $state; # This happens when topic has no META:WORKFLOW...

    foreach my $t ( @{ $this->getTransitions($state) } ) {
        next unless $t->{attribute};
        if( $t->{attribute} =~ /(?:\W|^)ALLOWDELETECOMMENTS(?:\W|$)/ ) {
            $allow = $allow.$t->{action}.',';
        }
        if( $t->{attribute} =~ /(?:\W|^)SUGGESTDELETECOMMENTS(?:\W|$)/ ) {
            $suggest = $suggest.$t->{action}.',';
        }
        if( $t->{attribute} =~ /(?:\W|^)REMARK(?:\W|$)/ ) {
            $comment = $comment.$t->{action}.',';
        }
    }

    return ($allow, $suggest, $comment);
}

# Get the next state defined for the given current state and action
# (the first 2 columns of the transition table). The returned state
# will be undef if the transition doesn't exist, or is not allowed.
sub getNextState {
    my ( $this, $topic, $action ) = @_;
    unless($action) {Foswiki::Func::writeWarning("No action! topic: ".$topic); return undef;} # XXX
    my $currentState = $topic->getState();

    my $t = $this->getTransition($currentState, $action);
    return undef unless $t;

    unless($t->{attribute} && $t->{attribute} =~ m#\bIGNOREMANDATORY\b#) {
        return undef if scalar Foswiki::Plugins::ModacHelpersPlugin::getNonSatisfiedFormFields($topic->{meta});
    }

    my $allowed = $topic->expandMacros( $t->{allowed} );
    my $nextState = $topic->expandMacros( $t->{nextstate} );
    my $condition = $topic->expandMacros( $t->{condition} );
    if ( _isTrue($condition) && _isAllowed($allowed) && $nextState ) {
        return $nextState;
    }
    return undef;
}

# Get a task by name
sub getTask {
    my ( $this, $task ) = @_;

    foreach my $t (@{ $this->{tasks} }) {
        if(
                $t->{task} eq $task
        ) {
            return $t;
        }
    }

    Foswiki::Func::writeWarning("Task not found: '$task'");
    return undef;
}

# Get a task by state and action
sub getTaskForAction {
    my ( $this, $topic, $action ) = @_;

    my $currentState = $topic->getState();
    my $t = $this->getTransition($currentState, $action);
    if ($t) {
        my $allowed = $topic->expandMacros( $t->{allowed} );
        if ( _isAllowed($allowed)) {
            return $t->{task} || '';
        }
    }

    Foswiki::Func::writeWarning("No Task found for state '$currentState' and action '$action'");
    return '';
}

# Get the notify column defined for the given current state and action
# (the first 2 columns of the transition table). The returned list
# will be undef if the transition doesn't exist, or is not allowed.
sub getNotifyList {
    my ( $this, $topic, $action ) = @_;
    my $currentState = $topic->getState();
    my $t = $this->getTransition($currentState, $action);
    return unless $t;
    my $allowed = $topic->expandMacros( $t->{allowed} );
    if ( _isAllowed( $allowed )) {
        my $notifylist = $topic->expandMacros( $t->{notify} );
        return $notifylist;
    }
    return undef;
}

# Get the allow read column defined for the state.
sub getChangeACL {
    my ( $this, $topic, $state ) = @_;

    return undef unless $this->{states}{$state};

    return $topic->expandMacros($this->{states}{$state}->{allowedit});
}

# Get the default state for this workflow
sub getDefaultState {
    my $this = shift;
    return $this->{defaultState};
}

# Returns a hash with all the fields from the given state
sub getFields {
    my ( $this, $state ) = @_;

    return unless $state;
    return $this->{states}->{$state};
}

sub _topicAllows {
    my ( $this, $topic, $what ) = @_;

    my $allowed;
    my $state = $topic->getState();
    unless( $this->{states}->{$state} ) {
        Foswiki::Func::writeWarning("Error in Workflow for $topic->{web}.$topic->{topic}: state '$state' does not exist!");
        Foswiki::Plugins::KVPPlugin::_broadcast('%MAKETEXT{"Error in Workflow: state [_1] does not exist!" args="'.$state.'"}%');
        $allowed = 'nobody'; # This will empower admins
    } else {
        $allowed = $topic->expandMacros( $this->{states}->{$state}->{$what} );
        $allowed = 'nobody' if ($allowed !~ m#\S# && $this->{states}->{$state}->{$what} =~ m#\S#); # eg. formfield is empty
    }
    return _isAllowed($allowed);
}

# Determine if the current user is allowed to move a topic that is in
# the given state.
sub allowMove {
    my ( $this, $topic ) = @_;

    # Default to Allow Edit if there is no Allow Move.
    my $default = $this->{defaultState};
    if ( defined $this->{states}->{$default}->{'allowmove'} ) {
        return $this->_topicAllows( $topic, 'allowmove' );
    } else {
        return $this->_topicAllows( $topic, 'allowedit' );
    }
}

# Determine if the current user is allowed to edit a topic that is in
# the given state.
sub allowEdit {
    my ( $this, $topic ) = @_;

    return $this->_topicAllows( $topic, 'allowedit' );
}

# Returns the web.topic of this workflow.
sub getName {
    my ( $this ) = @_;

    return $this->{name};
}

# Get to contents of the given row (in workflow states) and topic for the current state.
sub getRow {
    my ( $this, $state, $row ) = @_;

    unless( $this->{states}{$state} ) {
        Foswiki::Func::writeWarning("Undefined state '$state'; known states are: ". join(' ', sort keys %{$this->{states}}));
        return '';
    }
    return $this->{states}->{$state}->{$row};
# XXX to expand or not to expand...
#    return $topic->expandMacros( $this->{states}->{$state}->{$row} );
}

# finds out if the current user is allowed to do something.
# They are allowed if their wikiname is in the
# (comma,space)-separated list $allow, or they are a member
# of a group in the list.
sub _isAllowed {
    my ($allow) = @_;

    #Modac: Hier knnte ein Abfangen von ACLDISCUSS, ACLCHANGE, ACLVIEW, ACLRENAME hin

    return 1 unless ($allow);

    # Always allow members of the admin group to edit
    return 1 if ( Foswiki::Func::isAnAdmin() );

    return 0 if ( $allow =~ /^\s*nobody\s*$/ );
    if($allow =~ /\bLOGGEDIN\b/ && not Foswiki::Func::isGuest()) {
        return 1;
    }

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

# Checking Condition in Transition Table
sub _isTrue {
    my ($condition) = @_;
    return 1 unless (defined $condition && $condition ne '');

    if ( Foswiki::Func::isTrue($condition) ) {
        return 1;
    }

    return 0;
}




sub _cleanField {
    my ($text) = @_;
    $text ||= '';
    $text = lc($text);
    $text =~ s/[^\w.]//gi;
    return $text;
}

1;
