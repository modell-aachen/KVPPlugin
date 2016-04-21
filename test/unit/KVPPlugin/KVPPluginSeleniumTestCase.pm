# See bottom of file for license and copyright information

package KVPPluginSeleniumTestCase;

use ModacSeleniumTestCase();
our @ISA = qw( ModacSeleniumTestCase );

use strict;
use warnings;

use Foswiki();
use Error qw ( :try );
use Foswiki::Plugins::KVPPlugin();
use KVPPlugin::Helper qw ( :attachments :webs WRKFLW R_C_WORKFLOW setup );

use constant COMMENTEXAMPLE => 'Comment made in selenium-testrun';

my $users;
my @attachments;

sub new {
    my ($class, @args) = @_;
    my $this = $class->SUPER::new('KVPPluginSeleniumTests', @args);

    return $this;
}

sub loadExtraConfig {
    my $this = shift;
    $this->SUPER::loadExtraConfig();
    $Foswiki::cfg{Plugins}{KVPPlugin}{Enabled} = 1;
}

sub set_up {
    my $this = shift;

    $this->SUPER::set_up();

    $this->{webs} = Helper::set_up_webs($this);

    our @attachments = Helper::set_up_attachments($this);
}

sub tear_down {
    my ( $this ) = @_;

    Helper::tear_down_attachments(\@attachments);

    unless ( $ENV{KEEPTESTWEBS} ) {
        Helper::tear_down_webs( $this, $this->{webs} );
    }

    $this->SUPER::tear_down();
}

sub verify_SeleniumRc_config {
    my $this = shift;
    $this->selenium->get(
        Foswiki::Func::getScriptUrl(
            $this->{test_web}, $this->{test_topic}, 'view'
        )
    );
    $this->login();
}

# Test if...
# ...the WORKFLOW-preference set in a template is beeing used.
sub verify_templatesSetsWorkflow {
    my ( $this ) = @_;

    $this->login();

    my $user = Helper::becomeAnAdmin($this);
    my $web = Helper::KVPWEB;
    my $topic = 'SimpleWorkflowTest';
    my $workflow = 'SimpleWorkflow';
    Foswiki::Func::saveTopic( $web, $workflow, undef, <<'WORKFLOW' );
---++ Defaults
%EDITTABLE{format="| text, 20 | text, 20 | text, 20 | text, 2 |"}%
| *State Type* | *Left Tab* | *Right Tab* | *Approved* |
| approved | Approved Page | Discussion | 1 |

---++ States
%EDITTABLE{format="| text, 20 | text, 30 | text, 30 | text, 50 | text, 30 | text, 15 |"}%
| *State* | *Allow Edit* | *Allow Move* | *Message* | *Allow Comment* | *State Type* |
| NEU | LOGGEDIN |  | This document is not yet in CIP. | LOGGEDIN | approved |
| DONE | LOGGEDIN |  | This document is done. | LOGGEDIN | approved |
 
---++ Transitions
%EDITTABLE{format="| text, 20 | text, 40 | text, 20 | text, 30 | text, 30 | text, 15 | text, 15 |"}%
| *State* | *Action* | *Next State* | *Allowed* | *Notify* | *Condition* | *Attribute* |
| NEU | Create | DONE | LOGGEDIN, Main.KeyUserGroup | | | NEW |

   * Set NOWYSIWYG=1
   * Set WORKFLOW=
   * Set ALLOWTOPICCHANGE=Main.AdminUser
WORKFLOW

    my $template = 'SimpleWorkflowTemplate';
    Foswiki::Func::saveTopic( $web, $template, undef, <<TEMPLATE );
%META:PREFERENCE{name="WORKFLOW" title="WORKFLOW" type="Set" value="$workflow"}%
TEMPLATE

    # now create the topic
    $this->selenium->get(
        Foswiki::Func::getScriptUrl(
            $web, 'WebCreateNewTopic', 'view', templatetopic=>$template, newtopic=>$topic, topictitle=>$topic, t => time()
        )
    );
    $this->{selenium}->find_element('input.foswikiSubmit', 'css')->click();
    my $ckeditor;
    try {
        # let's try CKEditor first
        $this->waitFor( sub { $this->{selenium}->execute_script('return jQuery(".CKEDITORReady").length'); }, 'CKEditor did not become ready' );
        $ckeditor = 1;
    } otherwise {
    };
    $this->setMarker();
    if($ckeditor) {
        $this->waitFor( sub { $this->{selenium}->execute_script('return jQuery(".CKEDITORReady").length'); }, 'CKEditor did not become ready' );
        $this->{selenium}->find_element('.cke_button__ma-save_icon,.cke_button__ma-save-color_icon', 'css')->click();
    } else {
        $this->waitFor( sub { try { $this->{selenium}->find_element('save', 'id')->is_displayed(); } otherwise { return 0; }; }, 'Save button did not become ready' );
        $this->{selenium}->find_element('save', 'id')->click();
    }

    $this->waitForPageToLoad();
    $this->assert( Foswiki::Func::expandCommonVariables("%WORKFLOWMETA%", $topic, $web) eq 'DONE' );
}

# Tests if...
# ...there is a link to create a discussion
# ...clicking it creates a discussion
# ...clicking it redirects to the discussion
sub verify_createDiscussionLink {
    my ( $this ) = @_;

    my $topic = 'CreateDiscussionLinkTest';
    my $web = Helper::KVPWEB;

    my $admin = Helper::becomeAnAdmin( $this );
    Helper::createWithState( $this, $web, $topic, 'FREIGEGEBEN' );
    $this->assert( !Foswiki::Func::topicExists( $web, "${topic}TALK") );

    $this->login();

    $this->selenium->get(
        Foswiki::Func::getScriptUrl(
            $web, $topic, 'view'
        )
    );
    $this->setMarker();
    $this->{selenium}->find_element('a.kvpForkLink', 'css')->click();
    $this->waitForPageToLoad();
    $this->assert( $this->{selenium}->get_current_url() =~ m#/$web/${topic}TALK$# );
    $this->assert( Foswiki::Func::topicExists( $web, "${topic}TALK" ) );
}

# Tests if...
# ...when one clicks on "Create new Discussion" but discussion already exists, one will be redirected
# ...the existing discussion will not be overwritten
sub verify_redirectDiscussionLink {
    my ( $this ) = @_;

    my $topic = 'RedirectForkTest';
    my $web = Helper::KVPWEB;

    my $admin = Helper::becomeAnAdmin( $this );
    Helper::createWithState( $this, $web, $topic, 'FREIGEGEBEN' );
    $this->assert( !Foswiki::Func::topicExists( $web, "${topic}TALK") );

    $this->login();

    $this->setMarker();
    $this->{selenium}->get(
        Foswiki::Func::getScriptUrl(
            $web, $topic, 'view'
        )
    );
    $this->waitForPageToLoad();

    # there should be a link visible now... creating discussion in background and THEN click the link
    Helper::createDiscussion( $this, $web, $topic );
    my ( $meta, $text ) = Foswiki::Func::readTopic( $web, "${topic}TALK" );
    $text = 'This discussion has changed';
    Foswiki::Func::saveTopic( $web, "${topic}TALK", $meta, $text );

    $this->setMarker();
    $this->{selenium}->find_element('a.kvpForkLink', 'css')->click();
    $this->waitForPageToLoad();
    $this->assert( $this->{selenium}->get_current_url() =~ m#${topic}TALK$# );
    $this->assert( $this->{selenium}->find_element('div.foswikiTopic', 'css')->get_text() =~ m#This discussion has changed# );
    $this->assert( Foswiki::Func::topicExists( $web, "/$web/${topic}TALK") );
}

# Tests if...
# ...one is redirected at the last forked topic when multiple newnames
sub verify_redirectMultipleDiscussionLink {
    my ( $this ) = @_;

    my $topic = 'RedirectMultipleForkTest';
    my $web = Helper::KVPWEB;
    $this->assert( !Foswiki::Func::topicExists( $web, "${topic}F1") );
    $this->assert( !Foswiki::Func::topicExists( $web, "${topic}F2") );
    $this->assert( !Foswiki::Func::topicExists( $web, "${topic}F3") );
    $this->assert( !Foswiki::Func::topicExists( $web, "${topic}F4") );

    my $text = <<TEXT;
   * %WORKFLOWFORK{newnames="%TOPIC%F1,%TOPIC%F2,%TOPIC%F3" label="Fork it"}%
   * %WORKFLOWFORK{newnames="%TOPIC%F1,%TOPIC%F4,%TOPIC%F3" label="Fork again"}%
TEXT

    my $admin = Helper::becomeAnAdmin( $this );
    Helper::createWithState( $this, $web, ${topic}, 'FREIGEGEBEN', $text );

    $this->login();

    $this->{selenium}->get(
        Foswiki::Func::getScriptUrl(
            $web, ${topic}, 'view'
        )
    );

    # first fork
    $this->setMarker();
    $this->{selenium}->find_element('Fork it', 'link')->click();
    $this->waitForPageToLoad();
    $this->assert( $this->{selenium}->get_current_url() =~ m#/$web/${topic}F3$#, "Did not redirect to forked topic; current url: ".$this->{selenium}->get_current_url() );

    # fork again and see if redirect is good
    $this->{selenium}->get(
        Foswiki::Func::getScriptUrl(
            $web, ${topic}, 'view'
        )
    );
    $this->setMarker();
    $this->{selenium}->find_element('Fork again', 'link')->click();
    $this->waitForPageToLoad();
    $this->assert( $this->{selenium}->get_current_url() =~ m#/$web/${topic}F3$# );

    # also check if topics were created
    $this->assert( Foswiki::Func::topicExists( $web, "${topic}F1") );
    $this->assert( Foswiki::Func::topicExists( $web, "${topic}F2") );
    $this->assert( Foswiki::Func::topicExists( $web, "${topic}F3") );
    $this->assert( Foswiki::Func::topicExists( $web, "${topic}F4") );
}

# Test if...
# ...I can visit every state in a standard workflow
sub verify_basicTransitions {
    my ( $this ) = @_;

    my $web = Helper::KVPWEB;
    my $topic = 'SeleniumBasicTransitions';

    $this->login();
    Helper::becomeAnAdmin($this);

    Helper::createWithState( $this, $web, $topic, 'ENTWURF', undef, $Foswiki::cfg{UnitTestContrib}{SeleniumRc}{Username} );
    seleniumBringToState( $this, $web, $topic, 'FREIGEGEBEN' );
    $this->{selenium}->find_element( 'a.kvpForkLink', 'css' )->click();
    seleniumBringToState( $this, $web, "${topic}TALK", 'FORMALE_PRUEFUNG' );
    seleniumTransition( $this, 'Request further revision' );
    seleniumTransition( $this, 'Request approval' );
    seleniumTransition( $this, 'Request further revision' );
    Helper::becomeAnAdmin($this); # create a new session, so topics get reloaded
    Helper::ensureState( $this, $web, "${topic}TALK", 'DISKUSSIONSSTAND' );
    seleniumBringToState( $this, $web, "${topic}TALK", 'FREIGEGEBEN' );
    $this->setMarker();
    $this->{selenium}->find_element( 'a.kvpForkLink', 'css' )->click();
    $this->waitForPageToLoad();
    seleniumTransition( $this, 'Discard discussion' );
}

# Tests if...
# ...JavaScript for REMOVECOMMENTS makes checkboxes (dis-)appear correctly
sub verify_removeCommentsJS {
    my ( $this ) = @_;

    my $topic = 'RemoveCommentBoxTest';
    my $workflow = 'RemarkCommentWorkflow';
    my $wtext = Helper::R_C_WORKFLOW;

    my $admin = Helper::becomeAnAdmin( $this );

    # setup topic and workflow
    Foswiki::Func::saveTopic( Helper::NONEW, $workflow, undef, $wtext );
    Foswiki::Func::saveTopic( Helper::NONEW, ${topic}, undef, <<TOPIC );
   * Set WORKFLOW = $workflow
TOPIC

    $this->login();

    # bring to state
    $this->{selenium}->get(
        Foswiki::Func::getScriptUrl(
            Helper::NONEW, $topic, 'view'
        )
    );
    $this->seleniumTransition( 'To allow/suggest delete comments' );

    # test checkboxes for select
    # select allowdelete, see if box appeared
    $this->WorkflowSelect( "allowdeletecomment" );
    $this->assert( !$this->{selenium}->find_element('WORKFLOWchkboxbox', 'id')->is_selected() );
    # select suggestdelete, see if box got selected
    $this->WorkflowSelect( "suggestdeletecomment" );
    $this->assert( $this->{selenium}->find_element('WORKFLOWchkboxbox', 'id')->is_selected() );
    # select back, see if box got unselected
    $this->WorkflowSelect( "allowdeletecomment" );
    $this->assert( !$this->{selenium}->find_element('WORKFLOWchkboxbox', 'id')->is_selected() );
    # select suggestdelete, see if box got selected again
    $this->WorkflowSelect( "suggestdeletecomment" );
    $this->assert( $this->{selenium}->find_element('WORKFLOWchkboxbox', 'id')->is_selected() );
    # select nodelete, see if box dissappears
    try {
        $this->assert( !$this->{selenium}->find_element('WORKFLOWchkboxbox', 'id')->is_selected() );
        $this->assert( 0, "There should be no box!" );
    }
    catch Error::Simple with {
    };
    $this->seleniumTransition( 'nodelete' );

    # test checkboxes for button
    # transition allowdelete, see if box unchecked
    $this->seleniumTransition( 'To allow delete comments' );
    $this->assert( !$this->{selenium}->find_element('WORKFLOWchkboxbox', 'id')->is_selected() );
    $this->seleniumTransition( 'allowdeletecomments', 'button' );
    # transition suggestdelete, see if box checked
    $this->seleniumTransition( 'To suggest delete comments' );
    $this->assert( $this->{selenium}->find_element('WORKFLOWchkboxbox', 'id')->is_selected() );
    $this->seleniumTransition( 'suggestdeletecomments', 'button' );
    # transition no delete, see if box unvisible
    $this->seleniumTransition( 'To no delete comments' );
    try {
        $this->assert( !$this->{selenium}->find_element('WORKFLOWchkboxbox', 'id')->is_selected() );
        $this->assert( 0, "There should be no box!" );
    }
    catch Error::Simple with {
    };
    $this->seleniumTransition( 'do not delete comments' );
}

# Tests if...
# ...transitions with (ALLOW|SUGGEST)REMOVECOMMENTS actually removes comments
sub verify_removeComments {
    my ( $this ) = @_;

    my $topic = 'RemoveCommentTest';
    my $workflow = 'RemarkCommentWorkflow';
    my $wtext = Helper::R_C_WORKFLOW;

    my $admin = Helper::becomeAnAdmin( $this );

    # setup topic and workflow
    Foswiki::Func::saveTopic( Helper::NONEW, $workflow, undef, $wtext );
    Foswiki::Func::saveTopic( Helper::NONEW, ${topic}, undef, <<TOPIC );
   * Set WORKFLOW = $workflow
TOPIC

    $this->login();

    # bring to state and make comment
    $this->selenium->get(
        Foswiki::Func::getScriptUrl(
            Helper::NONEW, $topic, 'view'
        )
    );
    $this->seleniumTransition( 'To allow/suggest delete comments' );
    $this->seleniumComment();
    $this->assert( $this->hasComment( Helper::NONEW, $topic ) );

    # these should keep the comment
    # allowdelete
    $this->seleniumTransition( 'allowdeletecomment' );
    $this->assert( $this->hasComment( Helper::NONEW, $topic ) );
    $this->seleniumTransition( 'To allow/suggest delete comments' );
    # suggestdelete - uncheck the box
    $this->WorkflowSelect( "suggestdeletecomment" );
    $this->xxxScrollToTransitionForm();
    $this->{selenium}->find_element( 'WORKFLOWchkboxbox', 'id' )->click();
    $this->setMarker();
    $this->{selenium}->find_element( 'a.KVPChangeStatus', 'css' )->click();
    $this->waitForPageToLoad();
    $this->assert( $this->hasComment( Helper::NONEW, $topic ) );
    $this->seleniumTransition( 'To allow/suggest delete comments' );
    # nodelete - no attribute
    $this->seleniumTransition( 'nodelete' );
    $this->assert( $this->hasComment( Helper::NONEW, $topic ) );
    $this->seleniumTransition( 'To allow/suggest delete comments' );

    # these should delete the comment
    # allowdelete - check the box
    $this->WorkflowSelect( "allowdeletecomment" );
    $this->xxxScrollToTransitionForm();
    $this->{selenium}->find_element( 'WORKFLOWchkboxbox', 'id' )->click();
    $this->setMarker();
    $this->{selenium}->find_element( 'a.KVPChangeStatus', 'css' )->click();
    $this->waitForPageToLoad();
    $this->assert( !$this->hasComment( Helper::NONEW, $topic ) );
    $this->seleniumComment();
    $this->seleniumTransition( 'To allow/suggest delete comments' );
    # suggestdelete
    $this->seleniumTransition( 'suggestdeletecomment' );
    $this->assert( !$this->hasComment( Helper::NONEW, $topic ) );
    $this->seleniumComment();
    $this->seleniumTransition( 'To allow/suggest delete comments' );
    # nodelete - no attribute
    $this->seleniumTransition( 'dodelete' );
    $this->assert( !$this->hasComment( Helper::NONEW, $topic ) );
}

# Checks (in backend) if a topic has a specific MetaCommentPlugin comment.
#
# Parameters:
#    * web: the web
#    * topic: the topic
#    * comment: comment text
sub hasComment {
    my ( $this, $web, $topic, $comment ) = @_;
    $comment ||= COMMENTEXAMPLE;

    my ( $meta, $text ) = Foswiki::Func::readTopic( $web, $topic );

    my @comments = $meta->find( 'COMMENT' );
    foreach my $eachcomment (@comments) {
        if( $eachcomment->{text} eq $comment ) {
            return 1;
        }
    }
    return 0;
}

# Makes a MetaCommentPlugin comment (via Selenium).
#
# Parameters:
#    * comment: comment text
#    * title: title for the comment
sub seleniumComment {
    my ( $this, $comment, $title ) = @_;

    $comment ||= COMMENTEXAMPLE;
    $title ||= 'Selenium test';

    foreach my $twisty ( $this->{selenium}->find_elements( '#modacComments span.twistyTrigger', 'css' ) ) {
        if ( $twisty->is_displayed() && $twisty->get_attribute( 'id' ) =~ m#commentlist\d*show# ) {
            $twisty->click();
            $this->waitFor( sub { !$twisty->is_displayed() } );
        }
    }
    $this->{selenium}->find_element( '[name=title]', 'css' )->send_keys( $title );
    $this->{selenium}->find_element( '[name=text]', 'css' )->send_keys( $comment );
    my $succeeded;
    my $attempts = 3;
    my $element = $this->{selenium}->find_element( '.cmtAddCommentForm div.foswikiFormButtons a.jqButton', 'css' );
    while(!$succeeded) {
        $element->click();
        try {
            $this->waitFor( sub { $this->{selenium}->execute_script('return jQuery("div#cmtComment1").length') }, 'Comment did not appear', undef, 10_000 );
            $succeeded = 1;
        } otherwise {
            if(!--$attempts) {
                my $e = shift;
                throw $e;
            }
        }
    }
    $this->waitFor( sub { $this->{selenium}->execute_script('return (jQuery(".blockUI.blockMsg:visible").length)?"0":"1"') }, 'Comment was not processed by JS' ); # XXX unpublished API
}

# Transitions a topic until it is in the requested state (via Selenium).
# Works for the standard workflow in that web only.
# Topic may be in any state possible in the workflow.
#
# Parameters:
#    * web: web the topic is in; may be Helper::KVPWEB or Helper::NONEW
#    * topic: the topic
#    * to: the desired state
sub seleniumBringToState {
    my ( $this, $web, $topic, $to ) = @_;

    $this->waitForPageToLoad();
    my @transitions = @{Helper::getNextStates( $this, $web, $topic )};

    my $state = shift @transitions;

    $this->selenium->get(
        Foswiki::Func::getScriptUrl(
            $web, $topic, 'view'
        )
    );
    $this->waitForPageToLoad();

    while ($state ne $to) {
        my $transition = shift @transitions;
        $this->assert($transition ne 'error', "Desired state for '$web.$topic' not found: $state");
        seleniumTransition($this, $transition);
        $state = shift @transitions;
        $this->recreateSession( $web, 'WebHome'); #$topic );
        if($state eq 'FREIGEGEBEN') {
            $this->assert(!Foswiki::Func::topicExists( $web, $topic ), "Discussion $web.$topic was not moved away") if $topic =~ m/TALK$/;
            $topic =~ s#TALK$##g;
        }
        Helper::ensureState($this, $web, $topic, $state);
    }
}

# Creates a new session for the current user.
#
# Parameters:
#    * web: the web
#    * topic: the topic
sub recreateSession {
    my ( $this, $web, $topic ) = @_;

    my $query = Unit::Request->new( { action=>'view', topic=>"$web.$topic" } );
    my $user = Foswiki::Func::getWikiName();
    $this->createNewFoswikiSession( $user, $query );
}

# Performs a transition by pressing the corresponding buttons (via Selenium).
# Page must already be opened.
#
# Parameters:
#    * transition: name of the action
#    * type: set to 'button' or 'select' to check the input type (optional)
sub seleniumTransition {
    my ( $this, $transition, $type ) = @_;

    my $element;
    if ( !$this->element_present( 'WORKFLOWmenu', 'id' ) ) {
        if ( $type ) {
            $this->assert ( $type eq 'button' );
        }
        # For some reason this does not work on Edge (neither does link_text):
        # $element = $this->{selenium}->find_element( $transition, 'link' );
        $element = $this->{selenium}->find_element( "//text()[contains(., '$transition')]/ancestor::a" );
    } else {
        if ( $type ) {
            $this->assert ( $type eq 'select' );
        }
        $this->WorkflowSelect( $transition );
        $element = $this->{selenium}->find_element( 'a.KVPChangeStatus', 'css' );
    }

    $this->xxxScrollToTransitionForm();

    my $attempts = 3; # On certain browsers in version 9 the click might fail
                      # randomly for no reason.
                      # Because this method is being called a lot it is worth
                      # retrying a bit so the test will still pass.
    my $succeeded;
    $this->setMarker();
    while(!$succeeded) {
        $element->click();
        try {
            $this->waitForPageToLoad();
            $succeeded = 1;
        } otherwise {
            if(!--$attempts) {
                my $e = shift;
                throw $e;
            }
        };
    }
}

# This should not be required, since selenium is supposed to scroll there automatically.
# However on edge this fails.
sub xxxScrollToTransitionForm {
    my ($this) = @_;

    $this->{selenium}->execute_script("var p = jQuery('form.KVPTransitionForm:first').closest('table').offset();window.scrollTo(p.left, p.top);");
}

# Selects an action by value in the workflow menue (via Selenium)
#
# Parameters:
#    * value: the name of the action
sub WorkflowSelect {
    my ( $this, $value) = @_;

    my $option;
    try {
        $option = $this->{selenium}->find_element( "select#WORKFLOWmenu option[value='$value']", 'css' );
    } otherwise {
        $this->assert(0, "Selection not available: $value");
    };
    $this->assert($option->is_enabled(), "Selection not enabled: $value");

    $this->{selenium}->execute_script("jQuery('select#WORKFLOWmenu').val('$value').change();");
}

# Checks if an element is present in the dom (via Selenium)
#
# Parameters:
#    * selector: the selector of the element
#    * type: type of selector
#
# Returns:
#    * 1 if present
#    * 0 if not present
sub element_present {
    my ( $this, $selector, $type ) = @_;

    try {
        return $this->{selenium}->find_element( $selector, $type );
    } otherwise {
        return 0;
    };
}

# Checks if an element is visible (via Selenium).
#
# Parameters:
#    * selector: the selector of the element
#    * type: type of selector
#
# Return:
#    * 1 if present and visible
#    * 0 if present but not visible
#    * 0 if not present
sub element_visible {
    my ( $this, $selector, $type ) = @_;

    my $e = $this->element_present( $selector, $type );
    return 0 unless $e;
    return $e->is_displayed();
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
