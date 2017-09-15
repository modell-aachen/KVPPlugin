# See bottom of file for license and copyright information
use strict;
use warnings;

package KVPPluginTests;

use FoswikiFnTestCase;
our @ISA = qw( FoswikiFnTestCase );

use strict;
use warnings;

use Foswiki();
use Error qw ( :try );
use Foswiki::Plugins::KVPPlugin();
use KVPPlugin::Helper qw ( :attachments :webs WRKFLW setup );

my $users;
my @attachments;

sub new {
    my ($class, @args) = @_;
    my $this = shift()->SUPER::new('KVPPluginTests', @args);
    return $this;
}

sub loadExtraConfig {
    my $this = shift;
    $this->SUPER::loadExtraConfig();
    $Foswiki::cfg{Plugins}{KVPPlugin}{Enabled} = 1;
}

# Set up the test fixture
sub set_up {
    my $this = shift;

    $this->SUPER::set_up();

    our $users = Helper::set_up_users($this);

    $this->{webs} = Helper::set_up_webs($this);

    @attachments = Helper::set_up_attachments($this);
}

sub tear_down {
    my $this = shift;

    Helper::tear_down_attachments(\@attachments);

    unless ( $ENV{KEEPTESTWEBS} ) {
        Helper::tear_down_webs( $this, $this->{webs} );
    }

    $this->SUPER::tear_down();
}

# Test if...
# ...a fork will apply the default suffix
# ...changing the default suffix creates a discussion with the new suffix
# ...the context 'KVPHasDiscussion' is set correctly
#
# Note: The default suffix must not be set to the default value (TALK) in configure.
sub test_suffixTests {
    my ( $this ) = @_;

    my $defaultSuffix = $Foswiki::cfg{Extensions}{KVPPlugin}{suffix};
    $this->assert_equals( 'TALK', $defaultSuffix, "Suffix has been changed form TALK to $defaultSuffix!" );

    my $user = Helper::becomeAnAdmin($this);

    my $web = Helper::KVPWEB;
    my $query = Unit::Request->new( { action=>'view', topic=>"$web.SuffixTest" } );

    # Fork with default-Suffix
    Helper::createWithState( $this, Helper::KVPWEB, 'SuffixTest', 'FREIGEGEBEN' );
    $this->createNewFoswikiSession( $user, $query, {view => 1} );
    $this->assert( !Foswiki::Func::expandCommonVariables("%IF{\"context KVPHasDiscussion\" then=\"1\" else=\"0\"}%"), "test-topic SuffixTest already has a discussion!" );
    Helper::createDiscussion( $this, Helper::KVPWEB, 'SuffixTest' );
    $this->assert(Foswiki::Func::topicExists( Helper::KVPWEB, 'SuffixTestTALK' ), "Could not find discussion with default suffix!");
    $this->createNewFoswikiSession( $user, $query, {view => 1} );
    $this->assert( Foswiki::Func::expandCommonVariables("%IF{\"context KVPHasDiscussion\" then=\"1\" else=\"0\"}%"), "Discussion with defaultsuffix does not set context!" );

    try {
        # Now fork with different suffix
        $Foswiki::cfg{Extensions}{KVPPlugin}{suffix} = 'AndNowForSomethingCompletelyDifferent';
        $this->createNewFoswikiSession( $user, $query, {view => 1} );
        $this->assert( !Foswiki::Func::expandCommonVariables("%IF{\"context KVPHasDiscussion\" then=\"1\" else=\"0\"}%"), "Context still reports discussion with default-suffix altough suffix changed!" );
        Helper::createDiscussion( $this, Helper::KVPWEB, 'SuffixTest' );
        $this->assert(Foswiki::Func::topicExists( Helper::KVPWEB, 'SuffixTestAndNowForSomethingCompletelyDifferent' ), "Could not find discussion with changed suffix!");
        $this->createNewFoswikiSession( $user, $query, {view => 1} );
        $this->assert( Foswiki::Func::expandCommonVariables("%IF{\"context KVPHasDiscussion\" then=\"1\" else=\"0\"}%"), "Context still does not report discussion with changed suffix!" );
    } finally {
        $Foswiki::cfg{Extensions}{KVPPlugin}{suffix} = $defaultSuffix;
    };
}

# Test if...
# ...a logged in user can edit a topic where LOGGEDIN is in "allow edit"
# ...a logged in user can transition a topic where LOGGEDIN may transition
# ...a logged in user can not edit a topic where neither LOGGEDIN nor his WikiName is in "allow edit"
sub test_loggedin {
    my ( $this ) = @_;

    our $users;

    my $user = $this->createNewFoswikiSession( $users->{test1} );
    Helper::createWithState( $this, Helper::KVPWEB, 'LoggedInTest', 'ENTWURF' );
    Foswiki::Func::saveTopic( Helper::KVPWEB, 'LoggedInTest', undef, "$users->{test1} edited this." );
    Helper::transition( $this, 'ENTWURF', 'Request approval', Helper::KVPWEB, 'LoggedInTest' );
    try {
        Foswiki::Func::saveTopic( Helper::KVPWEB, 'LoggedInTest', undef, "$users->{test1} edited this again." );
        $this->assert(0, "$users->{test1} is not supposed to be able to edit this topic!" );
    } catch Foswiki::OopsException with {
        my $e = shift;
        $this->assert( $e->{template} eq 'workflowerr' && $e->{def} eq 'topic_access', "Wrong Exception on denied save." );
    } catch Error::Simple with {
        $this->assert( 0, shift->stringify() || '' );
    };
    $this->assert( !Helper::transition( $this, 'INHALTLICHE_PRUEFUNG_ENTWURF', 'Approve contentual aspects of draft', Helper::KVPWEB, 'LoggedInTest', 1 ), "$users->{test1} is not supposed to be able to transition this topic!" );
}

# Test if...
# ...a new topic starts at workflow version 0
# ...first approval leads to version 1
# ...creating and approving a discussion leads to version 2
sub test_revision {
    my ( $this ) = @_;

    my $user = Helper::becomeAnAdmin($this);
    my $web = Helper::KVPWEB;
    my $topic = 'RevisionTest';
    my $talk = $topic.'TALK';
    my $queryTopic = Unit::Request->new( { action=>'view', topic=>"$web.$topic" } );
    my $queryDiscussion = Unit::Request->new( { action=>'view', topic=>"$web.$talk" } );

    # Check if initial topic creation is ok
    Helper::createWithState( $this, $web, $topic, 'ENTWURF' );
    $this->createNewFoswikiSession( $user, $queryTopic );
    $this->assert_equals( 0, Foswiki::Func::expandCommonVariables('%WORKFLOWMETA{"Revision"}%') );
    Helper::transition( $this, 'ENTWURF', 'Request approval', $web, $topic );
    $this->assert_equals( 0, Foswiki::Func::expandCommonVariables('%WORKFLOWMETA{"Revision"}%') );
    Helper::bringToState( $this, $web, $topic, 'FREIGEGEBEN' );
    $this->assert_equals( 1, Foswiki::Func::expandCommonVariables('%WORKFLOWMETA{"Revision"}%') );

    # Now lets see if discussion behaves nicely
    Helper::createDiscussion( $this, $web, $topic );
    $this->createNewFoswikiSession( $user, $queryDiscussion );
    $this->assert_equals( 1, Foswiki::Func::expandCommonVariables('%WORKFLOWMETA{"Revision"}%') );
    Helper::bringToState( $this, $web, $talk, 'FREIGEGEBEN' );
    $this->createNewFoswikiSession( $user, $queryTopic );
    $this->assert_equals( 2, Foswiki::Func::expandCommonVariables('%WORKFLOWMETA{"Revision"}%') );
}

# Test if...
# ...attaching to a non-existing topic creates a stub with preference 'WorkflowStub'
# ...saving a topic with preference 'WorkflowStub' creates a proper topic
sub test_attachToNewTopic {
    my ( $this ) = @_;

    my $user = Helper::becomeAnAdmin($this);

    my $topic = 'AttachToNewTopicTest';
    my $web = Helper::KVPWEB;
    my $attachment = 'attachment.txt';

    # Attach to create stub
    Foswiki::Func::saveAttachment( $web, $topic, $attachment, { file=>$attachments[0]->{stream} } );

    # check stub
    my ( $meta, $text ) = Foswiki::Func::readTopic( $web, $topic );
    $this->assert_equals( '1', $meta->getPreference( 'WorkflowStub' ) );

    # now create proper topic and check if transitioned ok and no longer stub
    ( $meta, $text ) = Foswiki::Func::readTopic( $web, $topic );
    Foswiki::Func::saveTopic( $web, $topic, $meta, "This is a newly created Topic" ); # XXX the $meta should be optional, however Foswiki 2.1 will mess up otherwise
    ( $meta, $text ) = Foswiki::Func::readTopic( $web, $topic );
    $this->assert( !$meta->getPreference( 'WorkflowStub' ) );
    $this->assert( $meta->hasAttachment( $attachment ) );
    Helper::ensureState( $this, $web, $topic, 'ENTWURF' );
    $this->assert( Foswiki::Func::readAttachment( $web, $topic, $attachment ) eq $attachments[0]->{text} );
}

# Test if...
# ...forking and accepting discussions preserves
# ...accepting a discussion replaces the attachment in the approved version
sub test_forkAndAcceptWithAttachment {
    my ( $this ) = @_;

    my $user = Helper::becomeAnAdmin($this);

    my $topic = 'ForkAndAcceptWithAttachmentTest';
    my $discussion = "${topic}TALK";
    my $web = Helper::KVPWEB;
    my $attachment = 'attachment.txt';

    # Create approved topic with attachment
    Helper::createWithState( $this, $web, $topic, 'ENTWURF' );
    Foswiki::Func::saveAttachment( $web, $topic, $attachment, { file=>$attachments[0]->{stream} } );
    Helper::bringToState( $this, $web, $topic, 'FREIGEGEBEN' );

    # Create discussion and see if attachment is present
    Helper::createDiscussion( $this, $web, $topic );
    my $read = Foswiki::Func::readAttachment( $web, $discussion, $attachment );
    $this->assert($read eq $attachments[0]->{text} );

    # Attach a different file, approve topic and see if attachment in original topic is updated
    Foswiki::Func::saveAttachment( $web, $topic, $attachment, { file=>$attachments[1]->{stream} } );
    Helper::bringToState( $this, $web, $topic, 'FREIGEGEBEN' );
    $read = Foswiki::Func::readAttachment( $web, $topic, $attachment );
    $this->assert($read eq $attachments[1]->{text} );
}

# Test if...
# ...condition column is evaluated when selecting the NEW transition
sub test_condition {
    my ( $this ) = @_;

    my $user = Helper::becomeAnAdmin($this);

    my $subweb = Helper::NONEW."/CondTest";
    { # scope
        my $webPref = $Foswiki::cfg{WebPrefsTopicName};
        my $workflowname = 'DocumentApprovalWorkflow';
        my $subwebObject = $this->populateNewWeb( $subweb, "_default" );
        $subwebObject->finish();
        Foswiki::Func::saveTopic( $subweb, $workflowname, undef, Helper::CONDWORKFLOW );
        my ( $meta, $text ) = Foswiki::Func::readTopic( Helper::KVPWEB, $webPref );
        $text =~ s#(WORKFLOW\h*=\h*).*#$1$subweb.$workflowname#g;
        Foswiki::Func::saveTopic( $subweb, $webPref, undef, $text );
    }

    # reload WebPreferences
    my $query = Unit::Request->new( { action=>'view', topic=>"$subweb" } );
    $this->createNewFoswikiSession( $user, $query );

    # Check if correct NEW-transition is beeing selected
    Foswiki::Func::saveTopic( $subweb, 'ConditionTestDokument', undef, "This should be a DOKUMENT" );
    Foswiki::Func::saveTopic( $subweb, 'ConditionTestTemplate', undef, "This should be a TEMPLATE" );
    $this->createNewFoswikiSession( $user, $query );
    $this->assert_equals( 'DOKUMENT', Foswiki::Func::expandCommonVariables("%WORKFLOWMETA{topic=\"$subweb.ConditionTestDokument\"}%") );
    $this->assert_equals( 'TEMPLATE', Foswiki::Func::expandCommonVariables("%WORKFLOWMETA{topic=\"$subweb.ConditionTestTemplate\"}%") );
}

# Test if...
# ...transitions that require agreement from multiple users work as intended
# ...percentages are handled correctly
# ...groups are handled correctly (only one agreement required for each group listed in 'Allowed')
sub test_proposed {
    my ($this) = @_;

    my $user = Helper::becomeAnAdmin($this);
    my $web = Helper::KVPWEB;

    {
        my $webPref = $Foswiki::cfg{WebPrefsTopicName};
        my $workflowname = 'ProposalWorkflow';
        Foswiki::Func::saveTopic($web, $workflowname, undef, Helper::PROPOSALWORKFLOW);
        # XXX this has unexpected contents compared to set_up_webs, investigate
        my ($meta, $text) = Foswiki::Func::readTopic($web, $webPref);
        $text =~ s#(WORKFLOW\h*=\h*).*#$1$web.$workflowname#g;
        Foswiki::Func::saveTopic($web, $webPref, undef, $text);
    }
    # reload WebPreferences
    my $query = Unit::Request->new({action=>'view', topic=>"$web"});
    $this->createNewFoswikiSession($user, $query);

    my $topic = 'ProposedTest1';
    my $ensureProposed = sub {
        my $currentState = Foswiki::Func::expandCommonVariables("\%WORKFLOWMETA{topic=\"$web.$topic\"}\%");
        my $action = shift;
        my $user = shift || $Foswiki::Plugins::SESSION->{user};
        my $filter = qr/\b$user\b/;
        my $value = Foswiki::Func::expandCommonVariables(qq[\%QUERY{"'$web.$topic'/META:WORKFLOWPROPONENTS[name='$currentState:$action'].value"}\%]);
        my $positive = shift;
        $positive = 1 unless defined $positive;
        if ($positive) {
            $this->assert_matches($filter, $value, "Expected user to be listed as proposer but they're not");
        } else {
            $this->assert_does_not_match($filter, $value, "Expected user to not be listed as proposer but they are");
        }
    };

    Helper::createWithState($this, $web, $topic);
    Helper::transition($this, 'DRAFT', 'Propose approval', $web, $topic, 1);
    Helper::ensureState($this, $web, $topic, 'DRAFT');
    # SMELL: admins are currently added to the list even if they're not listed
    # in 'Allowed', but should still be excluded from calculations.
    #$ensureProposed->('Propose approval', undef, 0);

    # Test the straightforward 100% case with no groups

    $this->createNewFoswikiSession('test1');
    Helper::transition($this, 'DRAFT', 'Propose approval', $web, $topic);
    Helper::ensureState($this, $web, $topic, 'DRAFT');
    $ensureProposed->('Propose approval');
    $this->createNewFoswikiSession('test2');
    Helper::transition($this, 'DRAFT', 'Propose approval', $web, $topic);
    Helper::ensureState($this, $web, $topic, 'DRAFT');
    $ensureProposed->('Propose approval');
    $this->createNewFoswikiSession('qm1');
    Helper::transition($this, 'DRAFT', 'Propose approval', $web, $topic);
    Helper::ensureState($this, $web, $topic, 'APPROVED');

    # Test 2/3 case with group, making sure the minimal number of proposals
    # works
    Helper::transition($this, 'APPROVED', 'Propose re-draft', $web, $topic);
    Helper::ensureState($this, $web, $topic, 'APPROVED');
    $this->createNewFoswikiSession('test2');
    Helper::transition($this, 'APPROVED', 'Propose re-draft', $web, $topic);
    Helper::ensureState($this, $web, $topic, 'DRAFT');

    # Test 2/3 case with group again, making sure a second proposal for the
    # same group has no effect on the calculation
    Helper::becomeAnAdmin($this);
    Helper::transition($this, 'DRAFT', 'Escape hatch', $web, $topic);
    $this->createNewFoswikiSession('qm1');
    Helper::transition($this, 'APPROVED', 'Propose re-draft', $web, $topic);
    Helper::ensureState($this, $web, $topic, 'APPROVED');
    $this->createNewFoswikiSession('qm2');
    Helper::transition($this, 'APPROVED', 'Propose re-draft', $web, $topic);
    Helper::ensureState($this, $web, $topic, 'APPROVED');
    $this->createNewFoswikiSession('test1');
    Helper::transition($this, 'APPROVED', 'Propose re-draft', $web, $topic);
    Helper::ensureState($this, $web, $topic, 'DRAFT');
}

# Test if...
# ...moving an approved topic moves it's discussion with it
# ...moving an approved topic where an old discussion is in the way introduces a numbered suffix
#
# Note: The default suffix must be set to the default value (TALK) in configure.
sub test_moveWithDiscussion {
    my ( $this ) = @_;

    my $user = Helper::becomeAnAdmin($this);

    my $defaultSuffix = $Foswiki::cfg{Extensions}{KVPPlugin}{suffix};
    $this->assert_equals( 'TALK', $defaultSuffix, "Suffix has been changed form TALK to $defaultSuffix!" );
    my $testtext = 'Test: MoveWithDiscussion';
    my $testtext2 = 'This is in my way!';
    my $web = Helper::KVPWEB;

    Helper::createWithState( $this, $web, 'MoveTest', 'FREIGEGEBEN', $testtext );

    # Move without discussion
    Foswiki::Func::moveTopic( $web, 'MoveTest', $web, 'MovedTest' );
    $this->assert( Foswiki::Func::topicExists( $web, 'MovedTest' ), "Topic wasn't moved, even without discussion!" );
    $this->assert( !Foswiki::Func::topicExists( $web, 'MoveTest' ), "Unmoved topic still exists, even without discussion!" );

    # Move with discussion
    my $discussion = Helper::createDiscussion( $this, $web, 'MovedTest' );
    Foswiki::Func::moveTopic( $web, 'MovedTest', $web, 'MovedAgainTest' );
    $this->assert( Foswiki::Func::topicExists( $web, 'MovedAgainTest' ), "Original topic wasn't moved!" );
    $this->assert( !Foswiki::Func::topicExists( $web, 'MovedTest' ), "Original topic still exists!" );
    $this->assert( Foswiki::Func::topicExists( $web, 'MovedAgainTestTALK' ), "Discussion wasn't moved with original topic!" );
    $this->assert( !Foswiki::Func::topicExists( $web, 'MovedTestTALK' ), "Unmoved discussion still exists!" );

    my ($meta, $text);
    try {
        # Lets move yet again when an old discussion is in the way
        $Foswiki::cfg{Extensions}{KVPPlugin}{suffix} = 'Hello';
        Foswiki::Func::saveTopic( $web, "MovedYetAgainTestTALK", undef, $testtext2.' 1' );
        $Foswiki::cfg{Extensions}{KVPPlugin}{suffix} = $defaultSuffix;
        Foswiki::Func::moveTopic( $web, 'MovedAgainTest', $web, 'MovedYetAgainTest' );
        $this->assert( Foswiki::Func::topicExists( $web, 'MovedYetAgainTest' ) );
        $this->assert( !Foswiki::Func::topicExists( $web, 'MovedAgainTest' ) );
        $this->assert( !Foswiki::Func::topicExists( $web, 'MovedAgainTestTALK' ) );
        ($meta, $text) = Foswiki::Func::readTopic( $web, 'MovedYetAgainTestTALK' );
        $this->assert( $text =~ m/\Q$testtext\E/ );
        ($meta, $text) = Foswiki::Func::readTopic( Helper::TRASH, "${web}MovedYetAgainTestTALK" );
        $this->assert( $text =~ m/\Q$testtext2\E 1/ );

        # Do it again and see if nubers rise correctly
        Foswiki::Func::moveTopic( $web, 'MovedYetAgainTest', $web, 'MovedAgainTest' );
        $this->assert( !Foswiki::Func::topicExists( $web, 'MovedYetAgainTest' ) );
        $this->assert( !Foswiki::Func::topicExists( $web, 'MovedYetAgainTestTALK' ) );
        $Foswiki::cfg{Extensions}{KVPPlugin}{suffix} = 'Hello';
        Foswiki::Func::saveTopic( $web, "MovedYetAgainTestTALK", undef, $testtext2.' 2' );
    } finally {
        $Foswiki::cfg{Extensions}{KVPPlugin}{suffix} = $defaultSuffix;
    };
    Foswiki::Func::moveTopic( $web, 'MovedAgainTest', $web, 'MovedYetAgainTest' );
    $this->assert( Foswiki::Func::topicExists( $web, 'MovedYetAgainTest' ) );
    $this->assert( !Foswiki::Func::topicExists( $web, 'MovedAgainTest' ) );
    $this->assert( !Foswiki::Func::topicExists( $web, 'MovedAgainTestTALK' ) );
    ($meta, $text) = Foswiki::Func::readTopic( $web, 'MovedYetAgainTestTALK' );
    $this->assert( $text =~ m/\Q$testtext\E/ );
    ($meta, $text) = Foswiki::Func::readTopic( Helper::TRASH, "${web}MovedYetAgainTestTALK" ); # this should be the old one
    $this->assert( $text =~ m/\Q$testtext2\E 1/ );
    ($meta, $text) = Foswiki::Func::readTopic( Helper::TRASH, "${web}MovedYetAgainTestTALK_1" ); # and this is the new one
    $this->assert( $text =~ m/\Q$testtext2\E 2/ );
}

# Test if...
# ...%WORKFLOWORIGIN% is calculated correctly.
sub test_origin {
    my ( $this ) = @_;

    Helper::becomeAnAdmin($this);

    Helper::createWithState( $this, Helper::KVPWEB, 'OriginTestEntwurf', 'ENTWURF' );
    $this->assert_equals( 'OriginTestEntwurf', Foswiki::Func::expandCommonVariables('%WORKFLOWORIGIN%') );
    Helper::createWithState( $this, Helper::KVPWEB, 'OriginTestApproved', 'FREIGEGEBEN' );
    $this->assert_equals( 'OriginTestApproved', Foswiki::Func::expandCommonVariables('%WORKFLOWORIGIN%') );
    Helper::createDiscussion( $this, Helper::KVPWEB, 'OriginTestApproved' );
    $this->assert_equals( 'OriginTestApproved', Foswiki::Func::expandCommonVariables('%WORKFLOWORIGIN%') );
    Helper::createWithState( $this, Helper::KVPWEB, 'OriginTestTALKedabout', 'FREIGEGEBEN' );
    $this->assert_equals( 'OriginTestTALKedabout', Foswiki::Func::expandCommonVariables('%WORKFLOWORIGIN%') );
    Helper::createDiscussion( $this, Helper::KVPWEB, 'OriginTestTALKedabout' );
    $this->assert( Foswiki::Func::topicExists( Helper::KVPWEB, 'OriginTestTALKedaboutTALK' ) );
    $this->assert_equals( 'OriginTestTALKedabout', Foswiki::Func::expandCommonVariables('%WORKFLOWORIGIN%') );
}

# Test if...
# ...in a standard workflow all states and transitions can be reached/executed correctly.
sub test_basicTransitions {
    my ( $this ) = @_;

    Helper::becomeAnAdmin($this);

    Helper::createWithState( $this, Helper::NONEW, 'CreatedDraft', 'ENTWURF' );
    Helper::createWithState( $this, Helper::NONEW, 'CreatedApproved', 'FREIGEGEBEN' );

    Helper::createWithState( $this, Helper::KVPWEB, 'CreatedDraft', 'ENTWURF' );
    Helper::createWithState( $this, Helper::KVPWEB, 'CreatedApproved', 'FREIGEGEBEN' );
    Helper::createDiscussion( $this, Helper::KVPWEB, 'CreatedApproved' );
    Helper::bringToState( $this, Helper::KVPWEB, 'CreatedApprovedTALK', 'FORMALE_PRUEFUNG' );
    Helper::transition( $this, 'FORMALE_PRUEFUNG', 'Request further revision', Helper::KVPWEB, 'CreatedApprovedTALK' );
    Helper::transition( $this, 'DISKUSSIONSSTAND', 'Request approval', Helper::KVPWEB, 'CreatedApprovedTALK' );
    Helper::transition( $this, 'INHALTLICHE_PRUEFUNG', 'Request further revision', Helper::KVPWEB, 'CreatedApprovedTALK' );
    Helper::ensureState( $this, Helper::KVPWEB, 'CreatedApprovedTALK', 'DISKUSSIONSSTAND' );
    Helper::bringToState( $this, Helper::KVPWEB, 'CreatedApprovedTALK', 'FREIGEGEBEN' );
    Helper::createDiscussion( $this, Helper::KVPWEB, 'CreatedApproved' );
    Helper::transition( $this, 'DISKUSSIONSSTAND', 'Discard discussion', Helper::KVPWEB, 'CreatedApprovedTALK' );
}

# Test if...
# ...an admin may edit/attach to topics where is not in "allow edit" column
sub test_adminMayEditApproved {
    my ( $this ) = @_;

    my $topic = 'ApprovedTopic';
    my $attachment = 'attachment.txt';
    my $user = Helper::becomeAnAdmin($this);

    Helper::createWithState( $this, Helper::KVPWEB, 'ApprovedTopic', 'FREIGEGEBEN', "My name is $user, you may delete this topic." );

    my ( $meta, $text ) = Foswiki::Func::readTopic( Helper::KVPWEB, $topic );
    $text .= '\nThis topic has been edited.\n';
    try {
        Foswiki::Func::saveTopic( Helper::KVPWEB, $topic, $meta, $text );
        Foswiki::Func::saveAttachment( Helper::KVPWEB, $topic, $attachment, { file=>$attachments[0]->{stream} } );
    } catch Foswiki::OopsException with {
        my $oops = shift;
        $this->assert(0, "Admin $user could not edit approved topic: ".$oops->stringify());
    };

    # check result
    ( $meta, $text ) = Foswiki::Func::readTopic( Helper::KVPWEB, $topic );
    $this->assert( $text =~ m/edited/ );
    $this->assert( $meta->hasAttachment( $attachment ) );
    $this->assert( Foswiki::Func::readAttachment( Helper::KVPWEB, $topic, $attachment ) eq $attachments[0]->{text} );
}

# Test if...
# ...the NEW transition is executed when creating a topic
# ...lack of a NEW transition inhibits creating topic for non-admins
# ...admins can still create topics, even if there is no NEW transition
# ...non-admins can create topics without NEW transition if allowed in configure
sub test_attributeNEW {
    my ( $this ) = @_;

    use constant TOPIC => 'TestTopicNEW';

    our $users;

    my $user = Helper::becomeAnAdmin($this);

    # with NEW transition
    Foswiki::Func::saveTopic( Helper::KVPWEB, TOPIC, undef, 'This should be a draft' );
    my $state = Foswiki::Func::expandCommonVariables("%WORKFLOWMETA%", TOPIC, Helper::KVPWEB );
    $this->assert_equals( 'ENTWURF', $state, 'Newly created topic did not do the NEW transition.' );

    # without NEW transition
    Foswiki::Func::saveTopic( Helper::NONEW, TOPIC, undef, 'This should be a new article' );
    $state = Foswiki::Func::expandCommonVariables("%WORKFLOWMETA%", TOPIC, Helper::NONEW );
    $this->assert_equals( 'NEU', $state, 'Newly created topic is not in first state.' );

    # check if nonadmins are beeing inhibited if there is no NEW transition
    my $query = Unit::Request->new( { action=>'view' } );
    $this->createNewFoswikiSession( $users->{test1}, $query );
    try {
        Foswiki::Func::saveTopic( Helper::NONEW, TOPIC."NotAllowed", undef, 'This shouldn\'t be possible' );
        $this->assert( 0, "Nonadmin could create an article although there was no NEW transition" );
    } catch Foswiki::OopsException with {
        my $e = shift;
        $this->assert( $e->{template} eq 'workflowerr' && $e->{def} eq 'topic_creation', "Wrong Exception on denied save." );
    }
    catch Error::Simple with {
        $this->assert( 0, shift->stringify() || '' );
    };
    # check if nonadmins are allowed if there is no NEW transition and force is disabled in configure
    try {
        $Foswiki::cfg{Plugins}{KVPPlugin}{NoNewRequired} = 1;
        $query = Unit::Request->new( { action=>'view' } );
        $this->createNewFoswikiSession( $users->{test1}, $query );
        Foswiki::Func::saveTopic( Helper::NONEW, TOPIC."NewNotForced" );
    } catch Foswiki::OopsException with {
        my $e = shift;
        $this->assert( 0, "Nonadmin could not create an article although NEW transition wasn't forced" );
    } catch Error::Simple with {
        $this->assert( 0, shift->stringify() || '' );
    } finally {
        $Foswiki::cfg{Plugins}{KVPPlugin}{NoNewRequired} = 0;
    };

    return;
}

# Test if...
# ...discarding a discussion throws it into trash
# ...trashed discussions get correct name/numbered suffix
sub test_discard {
    my ( $this ) = @_;

    my $topic = 'TestMüllDiscussion'; # just for kicks, throw in an umlaut
    my $talk = 'TestMüllDiscussionTALK';
    my $trash = Helper::TRASH;
    my $web = Helper::KVPWEB;

    my $user = Helper::becomeAnAdmin($this);

    Helper::createWithState( $this, $web, $topic, 'FREIGEGEBEN', "This is version A" );

    # run 1
    Helper::createDiscussion( $this, $web, $topic );
    my ( $meta, $text ) = Foswiki::Func::readTopic( $web, $talk );
    Foswiki::Func::saveTopic( $web, $talk, $meta, $text.'1' );
    Helper::transition( $this, 'DISKUSSIONSSTAND', 'Discard discussion', $web, $talk );
    $this->assert( !Foswiki::Func::topicExists( $web, $talk ), "First discussion was not trashed when discarded." );

    # run 2
    Helper::createDiscussion( $this, $web, $topic );
    ( $meta, $text ) = Foswiki::Func::readTopic( $web, $talk );
    Foswiki::Func::saveTopic( $web, $talk, $meta, $text.'2' );
    Helper::transition( $this, 'DISKUSSIONSSTAND', 'Discard discussion', $web, $talk );
    $this->assert( !Foswiki::Func::topicExists( $web, $talk ), "Second discussion was not trashed when discarded." );

    # run 3
    Helper::createDiscussion( $this, $web, $topic );
    ( $meta, $text ) = Foswiki::Func::readTopic( $web, $talk );
    Foswiki::Func::saveTopic( $web, $talk, $meta, $text.'3' );
    Helper::transition( $this, 'DISKUSSIONSSTAND', 'Discard discussion', $web, $talk );
    $this->assert( !Foswiki::Func::topicExists( $web, $talk ), "Third discussion was not trashed when discarded." );

    # check results...
    ( $meta, $text ) = Foswiki::Func::readTopic( $trash, "$web$talk" );
    $this->assert_equals( 'This is version A1', $text, "First discussion was not trashed correctly!" );
    ( $meta, $text ) = Foswiki::Func::readTopic( $trash, "$web${talk}_1" );
    $this->assert_equals( 'This is version A2', $text, "Second discussion was not trashed correctly!" );
    ( $meta, $text ) = Foswiki::Func::readTopic( $trash, "$web${talk}_2" );
    $this->assert_equals( 'This is version A3', $text, "Third discussion was not trashed correctly!" );
}

sub test_move_attribute_moves_topics {
    my ( $this ) = @_;

    my $topic = 'TestMoveTopic';
    my $talkTopic = 'TestMoveTopicTALK';
    my $web = Helper::KVPWEB;
    my $destinationWeb = Helper::TRASH;

    my $user = Helper::becomeAnAdmin($this);

    Helper::createWithState( $this, $web, $topic, 'FREIGEGEBEN', "Approved version" );
    Helper::createDiscussion($this, $web, $topic);

    Helper::transition( $this, 'DISKUSSIONSSTAND', 'Archive', $web, $talkTopic, 1);

    $this->assert(!Foswiki::Func::topicExists($web, $topic), "Approved topic was not removed from its original web");
    $this->assert(Foswiki::Func::topicExists($destinationWeb, $topic), "Approved topic was not moved to the destination web");
    $this->assert(!Foswiki::Func::topicExists($web, $talkTopic), "Talk topic was not removed from its original web");
    $this->assert(Foswiki::Func::topicExists($destinationWeb, $talkTopic), "Talk topic was not moved to the destination web");

    return;
}

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Author: Modell Aachen GmbH

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
