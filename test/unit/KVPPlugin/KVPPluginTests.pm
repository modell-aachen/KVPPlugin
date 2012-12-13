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
    $this->createNewFoswikiSession( $user, $query );
    $this->assert( !Foswiki::Func::expandCommonVariables("%IF{\"context KVPHasDiscussion\" then=\"1\" else=\"0\"}%"), "test-topic SuffixTest already has a discussion!" );
    Helper::createDiscussion( $this, Helper::KVPWEB, 'SuffixTest' );
    $this->assert(Foswiki::Func::topicExists( Helper::KVPWEB, 'SuffixTestTALK' ), "Could not find discussion with default suffix!");
    $this->createNewFoswikiSession( $user, $query );
    $this->assert( Foswiki::Func::expandCommonVariables("%IF{\"context KVPHasDiscussion\" then=\"1\" else=\"0\"}%"), "Discussion with defaultsuffix does not set context!" );

    try {
        # Now fork with different suffix
        $Foswiki::cfg{Extensions}{KVPPlugin}{suffix} = 'AndNowForSomethingCompletelyDifferent';
        $this->createNewFoswikiSession( $user, $query );
        $this->assert( !Foswiki::Func::expandCommonVariables("%IF{\"context KVPHasDiscussion\" then=\"1\" else=\"0\"}%"), "Context still reports discussion with default-suffix altough suffix changed!" );
        Helper::createDiscussion( $this, Helper::KVPWEB, 'SuffixTest' );
        $this->assert(Foswiki::Func::topicExists( Helper::KVPWEB, 'SuffixTestAndNowForSomethingCompletelyDifferent' ), "Could not find discussion with changed suffix!");
        $this->createNewFoswikiSession( $user, $query );
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
