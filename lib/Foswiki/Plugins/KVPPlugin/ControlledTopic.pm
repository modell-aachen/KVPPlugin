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

# Constructor
sub new {
    my ( $class, $workflow, $web, $topic, $meta, $text ) = @_;

    my $forkSuffix = Foswiki::Plugins::KVPPlugin::_WORKFLOWSUFFIX();

    my $this = bless(
        {
            workflow  => $workflow,
            web       => $web,
            topic     => $topic,
            meta      => $meta,
            text      => $text,
            state     => $meta->get('WORKFLOW'),
            history   => $meta->get('WORKFLOWHISTORY'),
            forkweb   => $web,
            forktopic => $topic . $forkSuffix,
        },
        $class
    );

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

# Get the current state of the workflow in this topic
sub getState {
    my $this = shift;
    return $this->{state}->{name} || $this->{workflow}->getDefaultState();
}

# Get the available actions from the current state
sub getActions {
    my $this = shift;
    return $this->{workflow}->getActions($this);
}

# Get attributes for the given actoin
sub getAttributes {
    my ($this, $action) = @_;
    return $this->{workflow}->getAttributes($this->{state}->{name}, $action);
}

sub getWorkflowMeta {
    my ( $this, $attributes ) = @_;
    return $this->{state}->{$attributes};
}

# Alex: Get the extra Mailinglist (People involved in the Discussion)
sub getConributors {
    my ($this, $state) = @_;

    $state ||= $this->{state}->{name};

    my $contributors = $this->{meta}->get( 'WRKFLWCONTRIBUTORS', $state);
    return '' unless $contributors;    

    return $contributors->{value};
}

# Add another user to the Mailinglist
sub addConributors {
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

sub purgeConributors {
    my ( $this ) = @_;
    $this->{meta}->remove( 'WRKFLWCONTRIBUTORS' );
}

# Will increase the WorkflowRev
sub nextRev {
    my ( $this ) = @_;
    $this->{state}->{Revision}++;
}

# Alex: Forkweb
sub setForkWeb {
    my ( $this, $forkweb ) = @_;
    $this->{forkweb}->{value} = $forkweb;
}

# Set the current state in the topic
# Alex: Bearbeiter hinzu
sub setState {
    my ( $this, $state, $version, $remark ) = @_;
    my $oldState = $this->{state}->{name};
    $this->{state}->{name} = $state;

    $this->{state}->{"LASTVERSION_$state"} = $version;
    $this->{state}->{"LASTPROCESSOR_$state"} = Foswiki::Func::getWikiUserName();
    $this->{state}->{"LEAVING_$oldState"} = Foswiki::Func::getWikiUserName() if($oldState);
    $this->{state}->{"LASTTIME_$state"} =
      Foswiki::Time::formatTime( time(), '$day.$mo.$year', 'servertime' );

    $this->{state}->{Remark} = $remark || '';

    $this->{meta}->putKeyed( "WORKFLOW", $this->{state} );

    ## set accesspermissions to the ones defined in the table
    #my $writeAcls = $this->{workflow}->getChangeACL($this, $state);
    #$this->{meta}->putKeyed("PREFERENCE",
    #                      { name => 'ALLOWTOPICCHANGE', value => $writeAcls }) if ($writeAcls);
    #my $viewAcls = $this->{workflow}->getViewACL($this, $state);
    #$this->{meta}->putKeyed("PREFERENCE",
    #                      { name => 'ALLOWTOPICVIEW', value => $viewAcls }) if ($viewAcls);
    # manage comments
    my $allowComment = $this->{workflow}->getRow($this, 'allowcomment');
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

# Get the appropriate message for the current state
sub getStateMessage {
    my $this = shift;
    return $this->{workflow}->getMessage( $this->getState() );
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
    return $this->{workflow}->getNextState( $this, $action );
}

# Some day we may handle the can... functions indepedently. For now,
# they all check editability thus....
sub isModifyable {
    my $this = shift;

    return $this->{isEditable} if defined $this->{isEditable};

    # See if the workflow allows an edit
    unless (defined $this->{isEditable}) {
        $this->{isEditable} = (
            # Does the workflow permit editing?
            $this->{workflow}->allowEdit($this)
            # Does Foswiki permit editing?
            && Foswiki::Func::checkAccessPermission(
                'CHANGE', $Foswiki::Plugins::SESSION->{user},
                $this->{text}, $this->{topic}, $this->{web},
                $this->{meta})
        ) ? 1 : 0;
    }
    return $this->{isEditable};
}

# Get (first) action that leads to a fork
sub getActionWithAttribute {
    my ( $this, $attribute ) = @_;
    return $this->{workflow}->getActionWithAttribute($this, $attribute);
}

# Indicates if all comments will be removed if this action is executed on the state
sub isRemovingComments {
    my ( $this, $state, $action ) = @_;
    return $this->{workflow}->hasAttribute($state, $action, 'FORCEDELETECOMMENTS');
}

sub getTransitionAttributes {
    my ( $this ) = @_;
    return $this->{workflow}->getTransitionAttributes($this->{state}->{name});
}

# Check if the topic is allowed to fork
sub isForkable {
    my $this = shift;

    unless (defined $this->{isAllowingFork}) {
        $this->{isAllowingFork} = 
             # Allow forking if there is an action for it
             ($this->{workflow}->getActionWithAttribute($this, 'FORK')) ? 1 : 0;
    }
    return $this->{isAllowingFork};
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
    my ($this, $row) = @_;
    return $this->{workflow}->getRow($this, $row);
}

# Signals if the user may change the mailing list
sub getChangeMail {
    my ($this) = @_;

    return $this->{workflow}->getChangeMail($this);
}

# Will return the view template that should be used for current state
# Will prefer entry in workflow table over stored value and
# return undef if none was found.
sub getViewTemplate {
    my ($this) = @_;

    my $template = $this->{workflow}->getRow($this, 'viewtemplate');
# erstmal nicht:    $template = $this->{meta}->get('WORKFLOWTEMPLATE') unless $template;
    
    return undef unless $template;

    return $this->expandMacros($template);
}

# if the form employed in the state arrived after after applying $action
# is different to the form currently on the topic.
sub newForm {
    my ( $this, $action ) = @_;
    my $form = $this->{workflow}->getNextForm( $this, $action );
    my $oldForm = $this->{meta}->get('FORM');

    # If we want to have a form attached initially, we need to have
    # values in the topic, due to the form initialization
    # algorithm, or pass them here via URL parameters (take from
    # initialization topic)
    return ( $form && ( !$oldForm || $oldForm ne $form ) ) ? $form : undef;
}

# change the state of the topic. Does *not* save the updated topic, but
# does notify the change to listeners.
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
    my $form = $this->{workflow}->getNextForm( $this, $action );
    my $notify = $this->{workflow}->getNotifyList( $this, $action );

    my ( $revdate, $revuser, $version ) = $this->{meta}->getRevisionInfo();
    if (ref($revdate) eq 'HASH') {
        my $info = $revdate;
        ( $revdate, $revuser, $version ) =
          ( $info->{date}, $info->{author}, $info->{version} );
    }

    $this->setState($state, $version, $remark);

    my $fmt = Foswiki::Func::getPreferencesValue("WORKFLOWHISTORYFORMAT")
      || '<br>$state -- $date';
    $fmt =~ s/\$wikiusername/Foswiki::Func::getWikiUserName()/geo;
    $fmt =~ s/\$state/$this->getState()/goe;
    $fmt =~ s/\$date/$this->{state}->{"LASTTIME_$state"}/geo;
    $fmt =~ s/\$rev/$this->{state}->{"LASTVERSION_$state"}/geo;
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
    
    if ($form) {
        #$this->{meta}->put( "FORM", { name => $form } );
    }    # else leave the existing form in place

    # Send mails
    if ($notify) {
        # Expand vars in the notify list. This supports picking up the
        # value of the notifees from the topic itself.
        $notify = $this->expandMacros($notify);

        # Set Language
        my $language = $Foswiki::cfg{Extensions}{KVPPlugin}{MailLanguage};
        if($language) {
            Foswiki::Func::setPreferencesValue( 'LANGUAGE', $language );            
        }
        
        # Dig up the bodies
        $notify =~ s#^\s*|\s*$##g;
        my @groups = split( /\s*,\s*/, $notify );
        my @persons;
        my @emails;
        
        # Alex: Get Users from Groups
        foreach my $group (@groups) {
            next unless $group;
            if ( Foswiki::Func::isGroup($group)) {
                my $it = Foswiki::Func::eachGroupMember($group);
                while ($it->hasNext()) {
                    my $user = $it->next();
                    push( @persons, $user);
                }
            }
            # Alex: Handler fr Nicht-Gruppen
            else {
                #Alex: Debug
                push( @persons, $group);
            }
        }
        
        # Should be enough to del_double mail adresses: @persons = del_double(@persons);

        # Alex: Emailadressen auslesen
        foreach my $who (@persons) {
            if ( $who =~ /^$Foswiki::regex{emailAddrRegex}$/ ) {
                push( @emails, $who );
            }
            else {
                $who =~ s/^.*\.//;    # web name?
                my @list = Foswiki::Func::wikinameToEmails($who);
                if ( scalar(@list) ) {
                    push( @emails, @list );
                }
                else {
                    Foswiki::Func::writeWarning( __PACKAGE__
                          . " cannot send mail to '$who'"
                          . " - cannot determine an email address" );
                }
            }

        }
        
        # Alex: Email Doubletten verhindern:
        @emails = del_double(@emails);

        # Alex: Emails versenden
        if ( scalar(@emails) ) {
            # Have a list of recipients
            my $text = Foswiki::Func::loadTemplate('mailworkflowtransition');
            Foswiki::Func::setPreferencesValue(
                'EMAILTO',
                join( ', ', @emails )
            );
            Foswiki::Func::setPreferencesValue(
                'TARGET_STATE',
                $this->getState()
            );
            $text = $this->expandMacros($text);
            my $errors = Foswiki::Func::sendEmail( $text, 5 );
            if ($errors) {
                Foswiki::Func::writeWarning(
                    'Failed to send transition mails: ' . $errors
                );
            }
        }
        Foswiki::Func::writeWarning("Topic: '$this->{web}.$this->{topic}' Transition: '$action' Notify column: '$notify' Mails: ".join(", ", @emails)) if ($Foswiki::cfg{Extensions}{KVPPlugin}{MonitorMails});
    } else {
        Foswiki::Func::writeWarning("Topic: '$this->{web}.$this->{topic}' Transition: '$action' Notify column: empty") if ($Foswiki::cfg{Extensions}{KVPPlugin}{MonitorMails});
    }

    return undef;
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
    Foswiki::Func::saveTopic(
        $this->{web}, $this->{topic}, $this->{meta},
        $this->{text}, $options 
    );
}

# Alex: Alle doppelten Werte aus einem Array lschen
sub del_double{
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
    $text =
      Foswiki::Func::expandCommonVariables( $text, $this->{topic}, $this->{web},
        $this->{meta} );
    $c->{can_render_meta} = $memory;
    return $text;
}

1;
