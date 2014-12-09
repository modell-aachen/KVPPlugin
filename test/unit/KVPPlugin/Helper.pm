# See bottom of file for license and copyright information
use strict;
use warnings;
use Exporter 'import';

package Helper;

our @EXPORT_OK = qw ( KVPWEB NONEW TRASH WRKFLW ATTACHMENTTEXT1 ATTACHMENTTEXT2 WORKFLOW CONDWORKFLOW R_C_WORKFLOW set_up_users set_up_webs set_up_attachments );
our %EXPORT_TAGS = (
    attachments => [ 'set_up_attachments' ],
    webs => [ 'KVPWEB', 'NONEW', 'TRASH' ],
    setup => [ 'set_up_users', 'set_up_webs' ]
);

use Foswiki();
use Error qw ( :try );
use Foswiki::Plugins::KVPPlugin();

use constant KVPWEB => 'TemporaryKVPTestWeb';
use constant NONEW  => KVPWEB.'NoNew';
use constant TRASH  => KVPWEB.'Trash';
use constant WRKFLW => 'DocumentApprovalWorkflow';
use constant ATTACHMENTTEXT1 => 'This will be attached in a UnitTest run and can be safely removed.';
use constant ATTACHMENTTEXT2 => 'This is another file, that will be attached in a UnitTest run and can be safely removed.';

use constant WORKFLOW => <<'WORKFLOW';
---++ Defaults
%EDITTABLE{format="| text, 20 | text, 20 | text, 20 | text, 2 |"}%
| *State Type* | *Left Tab* | *Right Tab* | *Approved* |
| approved | Approved Page | Discussion | 1 |
| discussion | Approved Page | Discussion | 0 |
| draft | Approved Page | Draft | 0 |

---++ States
%EDITTABLE{format="| text, 20 | text, 30 | text, 30 | text, 50 | text, 30 | text, 15 |"}%
| *State* | *Allow Edit* | *Allow Move* | *Message* | *Allow Comment* | *State Type* |
| NEU | LOGGEDIN | Main.KeyUserGroup, %WORKFLOWMETA{LASTPROCESSOR_NEU}% | This document is not yet in CIP. | LOGGEDIN | draft |
| ENTWURF | LOGGEDIN | Main.KeyUserGroup, %WORKFLOWMETA{LASTPROCESSOR_NEU}% | This document is a draft. | LOGGEDIN | draft |
| FREIGEGEBEN | nobody | %META{"formfield" name="Seitenverantwortlicher"}%, Main.KeyUserGroup | This document has been approved. | | approved |
| DISKUSSIONSSTAND | Main.KeyUserGroup, Main.AllUserGroup, LOGGEDIN |  | This document is currently being revised. | LOGGEDIN | discussion |
| VERWORFEN | nobody | Main.KeyUserGroup | This document has beed discarded. | nobody | discussion |
| FORMALE_PRUEFUNG | Main.QMGroup, Main.KeyUserGroup | | This document is waiting for approval by the QM-department. | QMGroup, Main.KeyUserGroup | discussion |
| FORMALE_PRUEFUNG_ENTWURF | Main.QMGroup, Main.KeyUserGroup | QMGroup, Main.KeyUserGroup | This document is waiting for approval by the QM-department. | QMGroup, Main.KeyUserGroup | draft |
| INHALTLICHE_PRUEFUNG | %META{"formfield" name="Seitenverantwortlicher"}%, Main.KeyUserGroup | | This document is waiting for approval by the person in charge of the page. | %META{"formfield" name="Seitenverantwortlicher"}% | discussion |
| INHALTLICHE_PRUEFUNG_ENTWURF | %META{"formfield" name="Seitenverantwortlicher"}%, Main.KeyUserGroup | %META{"formfield" name="Seitenverantwortlicher"}%, Main.KeyUserGroup | This document is waiting for approval by the person in charge of the page. | %META{"formfield" name="Seitenverantwortlicher"}% | draft |
 
---++ Transitions
%EDITTABLE{format="| text, 20 | text, 40 | text, 20 | text, 30 | text, 30 | text, 15 | text, 15 |"}%
| *State* | *Action* | *Next State* | *Allowed* | *Notify* | *Condition* | *Attribute* |
| NEU | Create | ENTWURF | LOGGEDIN, Main.KeyUserGroup | | | NEW |
| NEU | Put under CIP | ENTWURF | LOGGEDIN, Main.KeyUserGroup | | | |
| ENTWURF | Request approval | INHALTLICHE_PRUEFUNG_ENTWURF | LOGGEDIN, Main.KeyUserGroup | | | |
| ENTWURF | Discard draft | VERWORFEN | LOGGEDIN, Main.KeyUserGroup | | | DISCARD |
| DISKUSSIONSSTAND | Request approval | INHALTLICHE_PRUEFUNG | LOGGEDIN, Main.KeyUserGroup | | | |
| DISKUSSIONSSTAND | Discard discussion | VERWORFEN | LOGGEDIN, Main.KeyUserGroup | | | DISCARD |
| FREIGEGEBEN | Discuss | DISKUSSIONSSTAND | LOGGEDIN, Main.KeyUserGroup | | | FORK |
| FORMALE_PRUEFUNG | Approve formal aspects of discussion | FREIGEGEBEN | QMGroup, Main.KeyUserGroup, %QUERY{FormalerPruefer}% | | | |
| FORMALE_PRUEFUNG | Request further revision | DISKUSSIONSSTAND | QMGroup, Main.KeyUserGroup, LOGGEDIN | | | REMARK |
| FORMALE_PRUEFUNG | Discard discussion | VERWORFEN | QMGroup, Main.KeyUserGroup, LOGGEDIN | | | DISCARD |
| FORMALE_PRUEFUNG_ENTWURF | Approve formal aspects of draft | FREIGEGEBEN | QMGroup, Main.KeyUserGroup, %QUERY{FormalerPruefer}% | | | |
| FORMALE_PRUEFUNG_ENTWURF | Request further revision | ENTWURF | QMGroup, Main.KeyUserGroup, LOGGEDIN | | | REMARK |
| FORMALE_PRUEFUNG_ENTWURF | Discard draft | VERWORFEN | QMGroup, Main.KeyUserGroup, LOGGEDIN | | | DISCARD |
| INHALTLICHE_PRUEFUNG | Approve contents of discussion | FORMALE_PRUEFUNG | %META{"formfield" name="Seitenverantwortlicher"}%, Main.KeyUserGroup | | | |
| INHALTLICHE_PRUEFUNG | Request further revision | DISKUSSIONSSTAND | %META{"formfield" name="Seitenverantwortlicher"}%, Main.KeyUserGroup, LOGGEDIN | | | REMARK |
| INHALTLICHE_PRUEFUNG | Discard discussion | VERWORFEN | %META{"formfield" name="Seitenverantwortlicher"}%, Main.KeyUserGroup, LOGGEDIN | | | DISCARD |
| INHALTLICHE_PRUEFUNG_ENTWURF | Approve contents of draft | FORMALE_PRUEFUNG_ENTWURF | %META{"formfield" name="Seitenverantwortlicher"}%, Main.KeyUserGroup | | | |
| INHALTLICHE_PRUEFUNG_ENTWURF | Request further revision | ENTWURF | %META{"formfield" name="Seitenverantwortlicher"}%, Main.KeyUserGroup, LOGGEDIN | | | REMARK |
| INHALTLICHE_PRUEFUNG_ENTWURF | Discard draft | VERWORFEN | %META{"formfield" name="Seitenverantwortlicher"}%, Main.KeyUserGroup, LOGGEDIN | | | DISCARD |
| VERWORFEN | Give article the accept status | FREIGEGEBEN | Main.KeyUserGroup | | | |

   * Set NOWYSIWYG=1
   * Set WORKFLOW=
   * Set ALLOWTOPICCHANGE=Main.AdminUser
WORKFLOW

use constant CONDWORKFLOW => <<'WORKFLOW';
---++ Defaults
%EDITTABLE{format="| text, 20 | text, 20 | text, 20 | text, 2 |"}%
| *State Type* | *Left Tab* | *Right Tab* | *Approved* |
| approved | Approved Page | Discussion | 1 |
| discussion | Approved Page | Discussion | 0 |
| draft | Approved Page | Draft | 0 |

---++ States
%EDITTABLE{format="| text, 20 | text, 30 | text, 30 | text, 50 | text, 30 | text, 15 |"}%
| *State* | *Allow Edit* | *Allow Move* | *Message* | *Allow Comment* | *State Type* |
| NEU | LOGGEDIN | Main.KeyUserGroup, %WORKFLOWMETA{LASTPROCESSOR_NEU}% | This document is not yet in CIP. | LOGGEDIN | draft |
| DOKUMENT | LOGGEDIN | Main.KeyUserGroup, %WORKFLOWMETA{LASTPROCESSOR_NEU}% | This document is a draft. | LOGGEDIN | draft |
| TEMPLATE | LOGGEDIN | Main.KeyUserGroup, %WORKFLOWMETA{LASTPROCESSOR_NEU}% | This document is a template. | LOGGEDIN | draft |

---++ Transitions
%EDITTABLE{format="| text, 20 | text, 40 | text, 20 | text, 30 | text, 30 | text, 15 | text, 15 |"}%
| *State* | *Action* | *Next State* | *Allowed* | *Notify* | *Condition* | *Attribute* |
| NEU | Create | DOKUMENT | LOGGEDIN, Main.KeyUserGroup | | %IF{"$TOPIC=~'.*Dokument$'" then="1" else="0"}% | NEW |
| NEU | Create template | TEMPLATE | Main.KeyUserGroup | | %IF{"$TOPIC=~'.*Template$'" then="1" else="0"}% | NEW |

   * Set NOWYSIWYG=1
   * Set WORKFLOW=
   * Set ALLOWTOPICCHANGE=Main.AdminUser
WORKFLOW

use constant R_C_WORKFLOW => <<'WORKFLOW';
---++ Defaults
%EDITTABLE{format="| text, 20 | text, 20 | text, 20 | text, 2 |"}%
| *State Type* | *Left Tab* | *Right Tab* | *Approved* |
| base | not used | Discussion | 0 |
| discussion | not used | Discussion | 0 |

---++ States
%EDITTABLE{format="| text, 20 | text, 30 | text, 30 | text, 50 | text, 30 | text, 15 |"}%
| *State* | *Allow Edit* | *Allow Move* | *Message* | *Allow Comment* | *State Type* |
| BASE | LOGGEDIN | Main.KeyUserGroup | This document is in it's base state. | LOGGEDIN | base |
| ALLOWSUGGESTC | LOGGEDIN | nobody | This document is under discussion. | LOGGEDIN | discussion |
| ALLOWC | LOGGEDIN | nobody | This document is under discussion. | LOGGEDIN | discussion |
| SUGGESTC | LOGGEDIN | nobody | This document is under discussion. | LOGGEDIN | discussion |
| NOC | LOGGEDIN | nobody | This document is under discussion. | LOGGEDIN | discussion |

---++ Transitions
%EDITTABLE{format="| text, 20 | text, 40 | text, 20 | text, 30 | text, 30 | text, 15 | text, 15 |"}%
| *State* | *Action* | *Next State* | *Allowed* | *Notify* | *Condition* | *Attribute* |
| BASE | To allow/suggest delete comments | ALLOWSUGGESTC | LOGGEDIN | | | |
| BASE | To allow delete comments | ALLOWC | LOGGEDIN | | | |
| BASE | To suggest delete comments | SUGGESTC | LOGGEDIN | | | |
| BASE | To no delete comments | NOC | LOGGEDIN | | | |
| ALLOWSUGGESTC | allowdeletecomment | BASE | LOGGEDIN | | | ALLOWDELETECOMMENTS |
| ALLOWSUGGESTC | suggestdeletecomment | BASE | LOGGEDIN | | | SUGGESTDELETECOMMENTS |
| ALLOWSUGGESTC | nodelete | BASE | LOGGEDIN | | | |
| ALLOWSUGGESTC | dodelete | BASE | LOGGEDIN | | | FORCEDELETECOMMENTS |
| ALLOWC | allowdeletecomments | BASE | LOGGEDIN | | | ALLOWDELETECOMMENTS |
| SUGGESTC | suggestdeletecomments | BASE | LOGGEDIN | | | SUGGESTDELETECOMMENTS |
| NOC | do not delete comments | BASE | LOGGEDIN | | | |

   * Set NOWYSIWYG=1
   * Set WORKFLOW=
   * Set ALLOWTOPICCHANGE=Main.AdminUser
WORKFLOW


sub loadExtraConfig {
    $Foswiki::cfg{Plugins}{KVPPlugin}{Enabled} = 1;
}

# Creates files to attach
sub set_up_attachments {
    my $other = shift;

    my $attachment1 = {};
    my $stream = File::Temp->new( UNLINK => 1 );
    print $stream ATTACHMENTTEXT1;
    $other->assert( $stream->close() );
    $attachment1->{filename} = $stream->filename;
    $attachment1->{stream} = $stream;
    $attachment1->{text} = ATTACHMENTTEXT1;

    my $attachment2 = {};
    $stream = File::Temp->new( UNLINK => 1 );
    print $stream Helper::ATTACHMENTTEXT2;
    $other->assert( $stream->close() );
    $attachment2->{filename} = $stream->filename;
    $attachment2->{stream} = $stream;
    $attachment2->{text} = ATTACHMENTTEXT2;

    return ( $attachment1, $attachment2 );
}

sub tear_down_attachments {
    my $attachments = shift;

    foreach my $attachment ( @$attachments ) {
        $attachment->{stream}->unlink_on_destroy(1);
    }
}

sub set_up_users {
    my $other = shift;

    my $users = {};

    # Users
    $other->registerUser( 'test1', 'Test', "One", 'testuser1@example.com' );
    $users->{test1} = $other->{session}->{users}->getCanonicalUserID('test1');
    $other->registerUser( 'qm1', 'Quality', "One", 'qm1@example.com' );
    $users->{qm1} = $other->{session}->{users}->getCanonicalUserID('qm1');

    return $users;
}

sub set_up_webs {
    my $other = shift;

    use Foswiki::AccessControlException;

    my $webs = {};

    # Set up test-webs and workflows
    $Foswiki::cfg{TrashWebName} = TRASH;
    my $query = Unit::Request->new('');
    my $user = becomeAnAdmin( $other );
    try {
        # Create TestWebs
        my $ps = KVPWEB;
        $webs->{$ps} = $other->populateNewWeb( $ps, "_default" );
        $webs->{$ps}->finish();
        $ps = NONEW;
        $webs->{$ps} = $other->populateNewWeb( $ps, "_default" );
        $webs->{$ps}->finish();
        $ps = TRASH;
        $webs->{$ps} = $other->populateNewWeb( $ps, "_default" );
        $webs->{$ps}->finish();

        # Create workflow
        my $standardworkflow = WORKFLOW;
        Foswiki::Func::saveTopic( KVPWEB, WRKFLW, undef, $standardworkflow);
        my $noNewTransitionWorkflow = $standardworkflow;
        # And a workflow without NEW transition
        my $nSubsts = $noNewTransitionWorkflow =~ s#^.*\|\h*NEW\h*\|\h*\n##mg;
        $other->assert($nSubsts == 1, 'Not exacly 1 NEW transition removed from standardworklow!');
        Foswiki::Func::saveTopic( NONEW, WRKFLW, undef, $noNewTransitionWorkflow);
        # Activate workflow
        { # scope
            my ( $prefMeta, $prefText ) = Foswiki::Func::readTopic( KVPWEB, $Foswiki::cfg{WebPrefsTopicName} );
            # Set workflow
            my $workflow = WRKFLW;
            my $nSubs = $prefText =~ s#^(\h{3,}\*\h+Set\h+WORKFLOW\h*=\h*).*$#$1$workflow#mg;
            unless ( $nSubs ) {
                $prefText .= "\n   * Set WORKFLOW = $workflow\n";
            }
            # and permissions
            $prefText =~ s#(\s{3,}\*\sSet ALLOWWEBVIEW).*#$1 =#g;
            $prefText =~ s#(\s{3,}\*\sSet ALLOWWEBCHANGE).*#$1 =#g;
            $prefText =~ s#(\s{3,}\*\sSet DENYWEBCHANGE).*#$1 =#g;

            # Set skin
            my ($pre, $skins);
            if ( $prefText =~ m#(\s{3,}\*\s+Set SKIN\s*=\s*)(.*)# ) {
                $pre = $1;
                $skins = $2;
            } else {
                $pre = '   * Set SKIN = ';
                $skins = 'kvp';
                $prefText .= "\n$pre$skins";
            }
            my $required = '';
            foreach my $item (qw( metacomment kvp modac ) ) {
                $required .= ",$item" unless $skins =~ m#$item#;
            }
            $prefText =~ s#\Q$pre$skins\E#$pre$skins$required#g;

            # save changes, will use same WebPreferences for both webs, as they are created
            # from the same template
            Foswiki::Func::saveTopic( KVPWEB,
                $Foswiki::cfg{WebPrefsTopicName}, undef, $prefText );
            Foswiki::Func::saveTopic( NONEW,
                $Foswiki::cfg{WebPrefsTopicName}, undef, $prefText );
        }
    }
    catch Foswiki::AccessControlException with {
        my $e = shift;
        die "???" unless $e;
        $other->assert( 0, ($e->can('stringify'))?$e->stringify():$e );
    }
    catch Error::Simple with {
        $other->assert( 0, shift->stringify() || '' );
    };

    return $webs;
}

sub tear_down_webs {
    my ( $other, $webs ) = @_;

    foreach my $web ( keys(%$webs) ) {
        $other->removeWebFixture( $other->{session}, $web );
    }
}

sub transition {
    my ( $this, $state, $transition, $web, $topic, $noassert ) = @_;

    die('missing parameters') unless $web && $state && $topic && $transition;
    my $user = Foswiki::Func::getWikiName();

    # For easy UnitTest debugging first check if topic has correct state
    $this->assert_equals( $state, Foswiki::Func::expandCommonVariables("%WORKFLOWMETA{topic=\"$web.$topic\"}%"), "Could not transition $web.$topic, because it is not in correct state!") unless $noassert;

    my $query = Unit::Request->new( { action => ['rest'], WORKFLOWACTION=>$transition, topic=>"$web.$topic", WORKFLOWSTATE=>$state } );
    $query->path_info( '/KVPPlugin/changeState' );
    $query->method('post');

    $this->createNewFoswikiSession( $user, $query );

    # check response
    my $UI_FN = $this->getUIFn('rest');
    my ($response) = $this->capture( $UI_FN, $this->{session} );
    my $path = Foswiki::Func::getScriptUrl( $web, $topic, 'view' );
    $path =~ s#\Q$Foswiki::cfg{Extensions}{KVPPlugin}{suffix}\E$##g if $transition =~ /(?:discard)|(?:Approve formal aspects of discussion)/i;
    my $nLoc =()= $response =~ m/Location/;
    my $ok = ($response =~ m/Status: 302/ && $response =~ m/Location: \Q$path\E/ && $nLoc == 1)?1:0;
    unless ($noassert) {
        $this->assert($ok, "$user could not change state of '$web.$topic' from '$state' with '$transition'!");
    }

    return $ok;
}

sub ensureState {
    my ( $this, $web, $topic, $state ) = @_;

    die("missing parameters") unless ($web && $topic && $state);

    my $currentState = Foswiki::Func::expandCommonVariables("%WORKFLOWMETA%", $topic, $web);
    $this->assert_equals( $state, $currentState, "Topic $web.$topic has not desired state '$state' (is: '$currentState')");
}

sub getNextStates {
    my ( $this, $web, $topic ) = @_;

    my @transitions = ( 'ENTWURF', 'Request approval', 'INHALTLICHE_PRUEFUNG_ENTWURF', 'Approve contents of draft', 'FORMALE_PRUEFUNG_ENTWURF', 'Approve formal aspects of draft', 'FREIGEGEBEN', 'error', 'DISKUSSIONSSTAND', 'Request approval', 'INHALTLICHE_PRUEFUNG', 'Approve contents of discussion', 'FORMALE_PRUEFUNG', 'Approve formal aspects of discussion', 'FREIGEGEBEN', 'error' );

    my $query = Unit::Request->new( { action=>'view', topic=>"$web.$topic" } );
    my $user = Foswiki::Func::getWikiName();
    $this->createNewFoswikiSession( $user, $query );
    my $state = Foswiki::Func::expandCommonVariables( "%WORKFLOWMETA{topic=\"$web.$topic\"}%" );

    while ($state ne $transitions[0]) {
        shift @transitions;
        $this->assert(scalar @transitions, "Topic $web.$topic is in unknown state: $state!");
    };

    return \@transitions;
}

sub bringToState {
    my ( $this, $web, $topic, $to ) = @_;

    my @transitions = @{getNextStates( $this, $web, $topic )};

    my $state = shift @transitions;

    while ($state ne $to) {
        my $transition = shift @transitions;
        $this->assert($transition ne 'error', "Desired state for '$web.$topic' not found: $state");
        transition($this, $state, $transition, $web, $topic);
        $state = shift @transitions;
        ensureState($this, $web, $topic, $state);
    }
}

sub createWithState {
    my ( $this, $web, $topic, $state, $text, $processowner, $qm ) = @_;

    $text ||= <<'TEXT';
This is a temporary UnitTest article and can be safely removed.
TEXT

    if ($processowner) {
        $qm = $processowner unless defined $qm;
        $text .= <<FORM;

%META:FORM{name="DokumentenForm"}%
%META:FIELD{name="Seitenverantwortlicher" attributes="" title="Seitenverantwortlicher" value="$processowner"}%
%META:FIELD{name="FormalerPruefer" attributes="" title="FormalerPruefer" value="$qm"}%
FORM
    }

    $topic ||= 'KVPUnitTestDefaultTopic';
    $web ||= KVPWEB;

    $this->assert( !Foswiki::Func::topicExists($web, $topic), "Topic to be created already exists!" );

    Foswiki::Func::saveTopic($web, $topic, undef, $text);

    return unless $state;

    if($web eq NONEW) {
        transition($this, 'NEU', 'Put under CIP', $web, $topic);
    }

    bringToState( $this, $web, $topic, $state );
}

sub becomeAnAdmin {
    my ( $this ) = @_;

    $this->createNewFoswikiSession( $Foswiki::cfg{AdminUserLogin} || 'AdminUser' );
    my $user = Foswiki::Func::getWikiName();
    $this->assert( Foswiki::Func::isAnAdmin($user), "Could not become AdminUser, tried as $user." );
    return $user;
}

sub createDiscussion {
    my ( $this, $web, $topic ) = @_;

    my $user = Foswiki::Func::getWikiName();
    my $forked = "$topic".$Foswiki::cfg{Extensions}{KVPPlugin}{suffix};

    $this->assert( !Foswiki::Func::topicExists($web, $forked), "Discussion already there!" );

    $this->assert_equals( 'FREIGEGEBEN', Foswiki::Func::expandCommonVariables("%WORKFLOWMETA{topic=\"$web.$topic\"}%"), "Cannot create discussion for $web.$topic, because it is not FREIGEGEBEN!" );

    my $query = Unit::Request->new( { action => ['rest'], topic=>"$web.$topic", lockdown=>'0' } );
    $query->path_info( '/KVPPlugin/fork' );
    $query->method('get');
    $this->createNewFoswikiSession( $user, $query );
    my $UI_FN = $this->getUIFn('rest');
    my $response = $this->capture( $UI_FN, $this->{session} );

    $this->assert( Foswiki::Func::topicExists($web, $forked), "No discussion created!" );
    $this->assert_equals( Foswiki::Func::expandCommonVariables( "%WORKFLOWMETA{topic=\"$web.$topic\"}% %WORKFLOWMETA{topic=\"$web.$forked\"}%" ), "FREIGEGEBEN DISKUSSIONSSTAND", "After forking: states are not correct!" );

    return $forked;
}

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Author: %$AUTHOR%

Copyright (C) 2008-2011 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
