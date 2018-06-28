# See bottom of file for license and copyright information
use strict;
use warnings;
use Exporter 'import';

package Helper;

our @EXPORT_OK = qw ( KVPWEB NONEW TRASH WRKFLW FORM_WRKFLW ATTACHMENTTEXT1 ATTACHMENTTEXT2 WORKFLOW CONDWORKFLOW R_C_WORKFLOW FORM_WORKFLOW_DEF set_up_users set_up_webs set_up_attachments STANDARD_FORM MANDATORY_FORM );
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
use constant FORM_WRKFLW => 'FormWorkflow';
use constant ATTACHMENTTEXT1 => 'This will be attached in a UnitTest run and can be safely removed.';
use constant ATTACHMENTTEXT2 => 'This is another file, that will be attached in a UnitTest run and can be safely removed.';
use constant STANDARD_FORM => 'DocumentForm';
use constant MANDATORY_FORM => 'MandatoryForm';

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
| ARCHIVIERT | Main.KeyUserGroup | Main.KeyUserGroup | This document is archived | | discussion |


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
| DISKUSSIONSSTAND | Archive | ARCHIVIERT | Main.KeyUserGroup | | | MOVE(TemporaryKVPTestWebTrash) |
| ARCHIVIERT | Restore | DISKUSSIONSSTAND | Main.KeyUserGroup | | | MOVE(TemporaryKVPTestWeb) |

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

use constant PROPOSALWORKFLOW => <<'WORKFLOW';
---++ Defaults
%EDITTABLE{format="| text, 20 | text, 20 | text, 20 | text, 2 |"}%
| *State Type* | *Left Tab* | *Right Tab* | *Approved* |
| approved | Approved Page | Discussion | 1 |
| discussion | Approved Page | Discussion | 0 |
| draft | Approved Page | Draft | 0 |

---++ States
%EDITTABLE{format="| text, 20 | text, 30 | text, 30 | text, 50 | text, 30 | text, 15 |"}%
| *State* | *Allow Edit* | *Allow Move* | *Message* | *Allow Comment* | *State Type* |
| NEW | LOGGEDIN | Main.KeyUserGroup, %WORKFLOWMETA{LASTPROCESSOR_NEU}% | This document is not yet in CIP. | LOGGEDIN | draft |
| DRAFT | LOGGEDIN | Main.KeyUserGroup, %WORKFLOWMETA{LASTPROCESSOR_NEU}% | This document is a draft. | LOGGEDIN | draft |
| APPROVED | LOGGEDIN | Main.KeyUserGroup, %WORKFLOWMETA{LASTPROCESSOR_NEU}% | This document is approved. | LOGGEDIN | approved |

---++ Transitions
%EDITTABLE{format="| text, 20 | text, 40 | text, 20 | text, 30 | text, 30 | text, 15 | text, 15 |"}%
| *State* | *Action* | *Next State* | *Allowed* | *Notify* | *Condition* | *Attribute* |
| NEW | Create | DRAFT | LOGGEDIN, Main.KeyUserGroup | | | NEW |
| DRAFT | Propose approval | APPROVED | test1, test2, qm1 | | | ALLOWEDPERCENT(100) |
| DRAFT | Propose approval 1 | APPROVED | test1 | | | ALLOWEDPERCENT(50) |
| DRAFT | Propose approval 2 | APPROVED | test1, test2 | | | ALLOWEDPERCENT(50) |
| DRAFT | Propose approval 3 | APPROVED | test1, test2, test3 | | | ALLOWEDPERCENT(50) |
| DRAFT | Propose approval 4 | APPROVED | test1, QMGroup | | | ALLOWEDPERCENT(50) |
| DRAFT | Propose approval 5 | APPROVED | QMGroup | | | ALLOWEDPERCENT(50) |
| DRAFT | Propose approval 6 | APPROVED | %QUERY{"Seitenverantwortlicher"}% | | | ALLOWEDPERCENT(50) |
| DRAFT | Propose approval 7 | APPROVED | %QUERY{"Seitenverantwortlicher"}%, %QUERY{"FormalerPruefer"}% | | | ALLOWEDPERCENT(50) |
| DRAFT | Propose approval 8 | APPROVED | %QUERY{"Seitenverantwortlicher"}%, test2 | | | ALLOWEDPERCENT(50) |
| DRAFT | Escape hatch | APPROVED | | | | |
| APPROVED | Propose re-draft | DRAFT | test1, test2, QMGroup | | | ALLOWEDPERCENT(60) |
| APPROVED | Escape hatch | DRAFT | | | | |

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

use constant FORM_WORKFLOW_DEF => <<'WORKFLOW' =~ s#STANDARD_FORM#STANDARD_FORM#ger =~ s#MANDATORY_FORM#MANDATORY_FORM#ger;
---++ Defaults
%EDITTABLE{format="| text, 20 | text, 20 | text, 20 | text, 2 |"}%
| *State Type* | *Left Tab* | *Right Tab* | *Approved* |
| approved | Approved Page | Discussion | 1 |
| discussion | Approved Page | Discussion | 0 |
| draft | Approved Page | Draft | 0 |

---++ States
%EDITTABLE{format="| text, 20 | text, 30 | text, 30 | text, 50 | text, 30 | text, 15 |"}%
| *State* | *Allow Edit* | *Allow Move* | *Message* | *Allow Comment* | *State Type* | *Form* |
| NEW | LOGGEDIN | LOGGEDIN | This document is not yet in CIP. | LOGGEDIN | draft | |
| DRAFT_NOT_MANDATORY | LOGGEDIN | LOGGEDIN | This document is a draft. | LOGGEDIN | draft | STANDARD_FORM |
| DRAFT_NO_FORM_CHANGE | LOGGEDIN | LOGGEDIN | This document is a draft. | LOGGEDIN | draft | |
| DRAFT_MANDATORY | LOGGEDIN | LOGGEDIN | This document is a draft. | LOGGEDIN | draft | MANDATORY_FORM |

---++ Transitions
%EDITTABLE{format="| text, 20 | text, 40 | text, 20 | text, 30 | text, 30 | text, 15 | text, 15 |"}%
| *State* | *Action* | *Next State* | *Allowed* | *Notify* | *Condition* | *Attribute* |
| NEW | Create | DRAFT_NOT_MANDATORY | LOGGEDIN | | | NEW |
| DRAFT_NOT_MANDATORY | Make mandatory | DRAFT_MANDATORY | LOGGEDIN | | | |
| DRAFT_NOT_MANDATORY | No mandatory change | DRAFT_NO_FORM_CHANGE | LOGGEDIN | | | |
| DRAFT_NO_FORM_CHANGE | Make mandatory | DRAFT_MANDATORY | LOGGEDIN | | | |
| DRAFT_MANDATORY | Make non-mandatory | DRAFT_NOT_MANDATORY | LOGGEDIN | | | |
| DRAFT_MANDATORY | No mandatory change | DRAFT_NO_FORM_CHANGE | LOGGEDIN | | | |
| DRAFT_MANDATORY | No mandatory change (ignore) | DRAFT_NO_FORM_CHANGE | LOGGEDIN | | | IGNOREMANDATORY |

   * Set NOWYSIWYG=1
   * Set WORKFLOW=
   * Set ALLOWTOPICCHANGE=Main.AdminUser
WORKFLOW

use constant FORM_DEF => <<'FORM';
| *Name* | *Type* | *Size* | *Values* | *Tooltip message* | *Attributes* |
| Seitenverantwortlicher | text | 30 | | | |
| FormalerPruefer | text | 30 | | | |
| TextField | text | 30 | | | |
FORM

use constant MANDATORY_FORM_DEF => <<'FORM';
| *Name* | *Type* | *Size* | *Values* | *Tooltip message* | *Attributes* |
| Seitenverantwortlicher | text | 30 | | | |
| FormalerPruefer | text | 30 | | | |
| TextField | text | 30 | | | M |
FORM

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
    $other->registerUser( 'test2', 'Test', "Two", 'testuser2@example.com' );
    $users->{test2} = $other->{session}->{users}->getCanonicalUserID('test2');
    $other->registerUser( 'test3', 'Test', "Three", 'testuser3@example.com' );
    $users->{test3} = $other->{session}->{users}->getCanonicalUserID('test3');
    $other->registerUser( 'qm1', 'Quality', "One", 'qm1@example.com' );
    $users->{qm1} = $other->{session}->{users}->getCanonicalUserID('qm1');
    $other->registerUser( 'qm2', 'Quality', "Two", 'qm2@example.com' );
    $users->{qm2} = $other->{session}->{users}->getCanonicalUserID('qm2');

    # hack hack hack
    local $Foswiki::Plugins::SESSION->{user} = 'BaseUserMapping_333';
    Foswiki::Func::addUserToGroup('qm1', 'QMGroup', 1);
    Foswiki::Func::addUserToGroup('qm2', 'QMGroup', 1);

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

        # Create DocumentForm
        my $form = FORM_DEF;
        Foswiki::Func::saveTopic( KVPWEB, STANDARD_FORM, undef, $form );
        my $mandatoryForm = MANDATORY_FORM_DEF;
        Foswiki::Func::saveTopic( KVPWEB, MANDATORY_FORM, undef, $mandatoryForm );

        # Create workflow
        my $standardworkflow = WORKFLOW;
        Foswiki::Func::saveTopic( KVPWEB, WRKFLW, undef, $standardworkflow);
        # And a workflow without NEW transition
        my $noNewTransitionWorkflow = $standardworkflow;
        my $nSubsts = $noNewTransitionWorkflow =~ s#^.*\|\h*NEW\h*\|\h*\n##mg;
        $other->assert($nSubsts == 1, 'Not exacly 1 NEW transition removed from standardworklow!');
        Foswiki::Func::saveTopic( NONEW, WRKFLW, undef, $noNewTransitionWorkflow);
        # And the form workflow
        my $formworkflow = FORM_WORKFLOW_DEF;
        Foswiki::Func::saveTopic( KVPWEB, FORM_WRKFLW, undef, $formworkflow);
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

    if (defined $processowner) {
        $qm = $processowner unless defined $qm;
        my $form = STANDARD_FORM;
        $text .= <<FORM;

%META:FORM{name="$form"}%
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

    my $query = Unit::Request->new( { action => ['rest'], topic=>"$web.$topic" } );
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
