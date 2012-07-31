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
            workflow => $workflow,
            web      => $web,
            topic    => $topic,
            meta     => $meta,
            text     => $text,
            state    => $meta->get('WORKFLOW'),
            history  => $meta->get('WORKFLOWHISTORY'),
            mailing  => $meta->get('WORKFLOWMAILINGLIST'),
	    wrev => $meta->get('WORKFLOWREV') || { 'MajorRev' => 0, 'MinorRev' => 0 },
            forkweb  => $web,
            forktopic => $topic . $forkSuffix,
        },
        $class
    );

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

sub getWorkflowMeta {
    my ( $this, $attributes ) = @_;

    if($attributes eq 'Revision') {
        return "$this->{wrev}->{'MajorRev'}.$this->{wrev}->{'MinorRev'}";
    }

    if (defined $this->{meta}->get('WORKFLOW')) {
    	return $this->{meta}->get('WORKFLOW')->{$attributes} || '';
    }
    return '';
}

# Alex: Get the extra Mailinglist (People involved in the Discussion)
sub getExtraNotify {
    my ($this, $type) = @_;

    if(!$type || $type eq 'ALL') {
        my $auto = $this->{mailing}->{AUTO};
        my $perm = $this->{mailing}->{PERMANENT};

        if($auto) {
            if($perm) {
                return "$auto,$perm";
            } else {
                return $auto;
            }
        }
        return $perm;
    }

    return $this->{mailing}->{$type};
}

# Alex: Set the extra Mailinglist (People involved in the Discussion)
sub setExtraNotify {
    my ( $this, $extraname, $type ) = @_;
    $type = 'AUTO' unless $type;
    # clear double entries
    my @extrapersons = split( /\s*,\s*/, $extraname );
    @extrapersons = del_double(@extrapersons);
    $extraname = join(',', @extrapersons);
    # assign
    $this->{mailing}->{$type} = $extraname;
    $this->{meta}->put( "WORKFLOWMAILINGLIST", $this->{mailing} );
}

# Add another user to the Mailinglist
sub addExtraNotify {
	my ( $this, $extraname, $type ) = @_;
	
	return unless $extraname;

	#Alex: Verbesserungsfähig?
	my $oldlist = $this->{mailing}->{$type};
        if($oldlist) {
          $this->setExtraNotify( $oldlist . "," . $extraname, $type );
	} else {
          $this->setExtraNotify( $extraname, $type );
	}
}

# Alex: Forkweb
sub setForkWeb {
	my ( $this, $forkweb ) = @_;
	#Alex: Verbesserungsfähig?
	$this->{forkweb}->{value} = $forkweb;
	#$this->{meta}->put( "WORKFLOWMAILINGLIST", $this->{extranotify} );
}

# Will increase the major revision and set minor revision to 0.
sub nextMajorRev {
	my ( $this ) = @_;
	$this->{wrev}->{'MinorRev'} = 0;
	$this->{wrev}->{'MajorRev'}++;
	$this->{meta}->put( 'WORKFLOWREV', $this->{wrev} );
}

# Set the current state in the topic
# Alex: Bearbeiter hinzu
sub setState {
    my ( $this, $state, $version ) = @_;
    my $oldState = $this->{state}->{name};
    $this->{state}->{name} = $state;
    $this->{state}->{"LASTVERSION_$state"} = $version;
    $this->{state}->{"LASTPROCESSOR_$state"} = Foswiki::Func::getWikiUserName();
    $this->{state}->{"LEAVING_$oldState"} = Foswiki::Func::getWikiUserName();
    $this->{state}->{"LASTTIME_$state"} =
      Foswiki::Time::formatTime( time(), '$day.$mo.$year', 'servertime' );
    $this->{meta}->putKeyed( "WORKFLOW", $this->{state} );
    $this->{wrev}->{'MinorRev'}++;
    $this->{meta}->put( 'WORKFLOWREV', $this->{wrev} );
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
                          { name => 'DISPLAYCOMMENTS', value => 'on' } );
        $this->{meta}->putKeyed("PREFERENCE",
                          { name => 'ALLOWTOPICCOMMENT', value => $allowComment } );
    } else {
        $this->{meta}->putKeyed("PREFERENCE",
                          { name => 'DISPLAYCOMMENTS', value => 'off' } );
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
                $this->{meta})) ? 1 : 0;
#             ) ? 1 : 0;
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

sub getDelActions {
    my ( $this ) = @_;
    return $this->{workflow}->getDelActions();
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

    

# Expand miscellaneous preferences defined in the workflow and topic
sub expandWorkflowPreferences {
    my $this = shift;
    my $url  = shift;
    my $key;
    foreach $key ( keys %{ $this->{workflow}->{preferences} } ) {
        if ( $key =~ /^WORKFLOW/ ) {
            $_[0] =~ s/%$key%/$this->{workflow}->{preferences}->{$key}/g;
        }
    }

    # show last version tags and last time tags
    while ( my ( $key, $val ) = each %{ $this->{state} } ) {
        $val ||= '';
        if ( $key =~ m/^LASTVERSION_/ ) {
            my $foo = CGI::a( { href => "$url?rev=$val" }, "revision $val" );
            $_[0] =~ s/%WORKFLOW$key%/$foo/g;

            # WORKFLOWLASTREV_
            $key =~ s/VERSION/REV/;
            $_[0] =~ s/%WORKFLOW$key%/$val/g;
        }
        elsif ( $key =~ /^LASTTIME_/ ) {
            $_[0] =~ s/%WORKFLOW$key%/$val/g;
        }
    }

    # Clean down any states we have no info about
    $_[0] =~ s/%WORKFLOWLAST(TIME|VERSION)_\w+%//g unless $this->debugging();
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

# removes the entries from AUTO in the mailinglist.
sub purgeExtraNotify {
    my ( $this ) = @_;
    my $list = {name => 'WORKFLOWMAILINGLIST', PERMANENT => $this->{mailing}->{PERMANENT}, AUTO => ""};
    $this->{meta}->putKeyed("WORKFLOWMAILINGLIST", $list);
    $this->{mailing} = $list;
}

# change the state of the topic. Does *not* save the updated topic, but
# does notify the change to listeners.
sub changeState {
    my ( $this, $action ) = @_;
    my $oldstate = $this->{state}->{name};

    my $state = $this->{workflow}->getNextState( $this, $action );
unless ($state) {$action = $action || ''; Foswiki::Func::writeWarning("changeState: No NextState! Action=".$action." currentState=".$this->{state}->{name}); return;} # XXX Debug
    #Alex: Es muss garantiert sein, dass die Form nicht leer ist (also " ")
    my $form = $this->{workflow}->getNextForm( $this, $action );
    my $notify = $this->{workflow}->getNotifyList( $this, $action );

    my ( $revdate, $revuser, $version ) = $this->{meta}->getRevisionInfo();
    if (ref($revdate) eq 'HASH') {
        my $info = $revdate;
        ( $revdate, $revuser, $version ) =
          ( $info->{date}, $info->{author}, $info->{version} );
    }

    $this->setState($state, $version);

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
    
    #Alex: Rodeeeeo!
    # Nicht mehr nach Spzifikation?
    #    $this->addExtraNotify( Foswiki::Func::getWikiUserName() );
    
    if ($form) {
        #$this->{meta}->put( "FORM", { name => $form } );
    }    # else leave the existing form in place

    # Send mails
    if ($notify) {
        # Expand vars in the notify list. This supports picking up the
        # value of the notifees from the topic itself.
        $notify = $this->expandMacros($notify);
		
        # Dig up the bodies
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
			        #Alex: Debug
			        #Foswiki::Func::writeWarning( __PACKAGE__
	                        #  . "Gruppenmitglied: '$user" );
			    }
        	}
        	# Alex: Handler für Nicht-Gruppen
        	else {
        		#Alex: Debug
        		#Foswiki::Func::writeWarning( __PACKAGE__
	                #          . " Notify Mitglied: $group" );
        		push( @persons, $group);
        	}
        	
        	# Alex notify und extranotify zusammenführen und doppelte Werte verrrrnichten!!!
			#foreach(@extrapersons) {
  			#	push(@persons,$_);
			#}
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
#Foswiki::Func::writeWarning("changeState mails: ".join(",", @emails));
        
        # Alex: Emails versenden
        if ( scalar(@emails) ) {
		Foswiki::Func::writeWarning("Mails: ".join(',', @emails));
            # Have a list of recipients
            my $text = Foswiki::Func::loadTemplate('mailworkflowtransition');
            Foswiki::Func::setPreferencesValue( 'EMAILTO',
                join( ', ', @emails ) );
            Foswiki::Func::setPreferencesValue( 'TARGET_STATE',
                $this->getState() );
            $text = $this->expandMacros($text);
            my $errors = Foswiki::Func::sendEmail( $text, 5 );
            if ($errors) {
                Foswiki::Func::writeWarning(
                    'Failed to send transition mails: ' . $errors );
            }
        }
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

# Alex: Alle doppelten Werte aus einem Array löschen
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
