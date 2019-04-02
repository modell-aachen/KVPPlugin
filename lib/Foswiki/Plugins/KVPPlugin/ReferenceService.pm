package Foswiki::Plugins::KVPPlugin::ReferenceService;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Meta ();
use Foswiki::Serialise ();

use JSON;

use Foswiki::Plugins::SolrPlugin;
use Foswiki::Plugins::ModacHelpersPlugin::Logger;

sub _calculateFinalDestinations {
    my ($fromWeb, $fromTopic, $attachmentMoves) = @_;

    my $moves = {};
    my $sources = {};
    foreach my $attachmentMove (@$attachmentMoves) {
        my $moveFrom = encodeAttachmentData($fromWeb, $fromTopic, $attachmentMove->{fromName});
        my $moveTo = $attachmentMove->{value};
        my $sourceList = $sources->{$moveTo} ||= [];
        if(exists $sources->{$moveFrom}) {
            foreach my $otherSource (@{$sources->{$moveFrom}}) {
                $moves->{$otherSource} = $moveTo;
                push @$sourceList, $otherSource;
            }
            delete $sources->{$moveFrom};
        }
        push @$sourceList, $moveFrom;
        $moves->{$moveFrom} = $moveTo unless exists $moves->{$moveFrom};
    }

    return $moves;
}

sub encodeAttachmentData {
    my ($web, $topic, $name) = @_;

    return "$web/$topic/$name";
}

sub decodeAttachmentData {
    my ($data) = @_;

    my ($web, $topic, $name) = $data =~ m#(.*)/(.*)/(.*)#;

    return ($web, $topic, $name);
}

sub handleReferencingAttachmentsOnApproval {
    my ($fromWeb, $discussionTopic, $appTopic, $attachmentMoves, $attachments) = @_;

    my @sortedAttachments = sort {$a->{date} <=> $b->{date}} @$attachmentMoves;

    my $finalMoves = _calculateFinalDestinations($fromWeb, $discussionTopic, \@sortedAttachments);

    my $handledAttachments = {};
    foreach my $attachmentMove (@sortedAttachments) {
        my $moveFrom = encodeAttachmentData($fromWeb, $discussionTopic, $attachmentMove->{fromName});
        my $finalMove = $finalMoves->{$moveFrom};
        my $fromName = $attachmentMove->{fromName};
        my ($toWeb, $toTopic, $toName) = decodeAttachmentData($finalMove);
        unless($toWeb && $toTopic && $toName) {
            logWarning("Could not determine destination for $moveFrom when approving");
            next;
        }
        my $toTopicNormalized = ($toWeb eq $fromWeb && $toTopic eq $discussionTopic) ? $appTopic : $toTopic;
        replaceOtherReferencingAttachmentLinks($fromWeb, $appTopic, $fromName, $toWeb, $toTopicNormalized, $toName);
        replaceOtherReferencingAttachmentLinks($fromWeb, $discussionTopic, $fromName, $toWeb, $toTopicNormalized, $toName);
        $handledAttachments->{$fromName} = 1;
    }

    foreach my $attachment (@$attachments) {
        my $attachmentName = $attachment->{name};
        next if $handledAttachments->{$attachmentName};
        replaceOtherReferencingAttachmentLinks($fromWeb, $discussionTopic, $attachmentName, $fromWeb, $appTopic, $attachmentName);
    }
}

sub updateAttachmentMoves {
    my ($oldWeb, $oldTopic, $newWeb, $newTopic) = @_;

    my ($newMeta) = Foswiki::Func::readTopic($newWeb, $newTopic);
    foreach my $attachmentMeta ($newMeta->find('FILEATTACHMENT')) {
        my $attachment = $attachmentMeta->{name};
        my $attachmentMove = encodeAttachmentData($oldWeb, $oldTopic, $attachment);
        my $search = "type:topic WORKFLOW_ATTACHMENTMOVE_lst:\"$attachmentMove\"";
        my $webTopics = _getTopicsFromSolr($search);
        foreach my $webTopic (@$webTopics) {
            my ($refWeb, $refTopic) = Foswiki::Func::normalizeWebTopicName(undef, $webTopic);
            my ($referencingMeta) = Foswiki::Func::readTopic($refWeb, $refTopic);
            updateAttachmentMoveMetadata($referencingMeta, {
                oldWeb => "$oldWeb/$oldTopic",
                oldTopic => $attachment,
                newWeb => "$newWeb/$newTopic",
                newTopic => $attachment,
            });
            $referencingMeta->save(minor => 1);
        }
    }
}

sub replaceOtherReferencingAttachmentLinks {
    my ($oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment) = @_;

    my $options = {
        oldWeb    => "$oldWeb/$oldTopic",
        oldTopic  => $oldAttachment,
        newWeb    => "$newWeb/$newTopic",
        newTopic  => $newAttachment,
        fullPaths => 0,
        noautolink => 1,
        inMeta => 1,
    };

    my $otherReferencingTopics = _getOtherReferencingTopics($oldWeb, $oldTopic, $oldAttachment);

    _updateReferringTopics($Foswiki::Plugins::SESSION, $otherReferencingTopics, \&Foswiki::UI::Rename::_replaceTopicReferences, $options) if scalar(@$otherReferencingTopics) > 0;
}

sub _getTopicsFromSolr {
    my ($query) = @_;

    my $solr = Foswiki::Plugins::SolrPlugin::getSearcher();
    my $rawResponse = $solr->solrSearch($query, {fields => 'webtopic'})->{raw_response};
    my $content = from_json($rawResponse->{_content});
    my $docs = $content->{response}->{docs};
    my @topics = map{$_->{webtopic}} @$docs;

    return \@topics;
}

sub _getOtherReferencingTopics {
    my ($oldWeb, $oldTopic, $oldAttachment) = @_;

    $oldWeb =~ s#/#.#g;
    my $attachmentMove = encodeAttachmentData($oldWeb, $oldTopic, $oldAttachment);
    my $search = "type:topic -webtopic:\"$oldWeb.$oldTopic\" (outgoingAttachment_lst:\"$oldWeb.$oldTopic/$oldAttachment\" OR outgoingAttachment_broken_lst:\"$oldWeb.$oldTopic/$oldAttachment\" OR WORKFLOW_ATTACHMENTMOVE_lst:\"$attachmentMove\")";
    return _getTopicsFromSolr($search);
}

sub replaceLocalAttachmentLinks {
    my ($session, $oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment, $oldMeta, $newMeta) = @_;

    my $metas = [$oldMeta || Foswiki::Meta->load( $session, $oldWeb, $oldTopic )];
    if($oldWeb ne $newWeb || $oldTopic ne $newTopic) {
        push @$metas, ($newMeta || Foswiki::Meta->load( $session, $newWeb, $newTopic ));
    }

    my $oldPubUrl = Foswiki::Func::getPubUrlPath($oldWeb, $oldTopic, undef, absolute => 1);
    my $oldPubUrlPath = Foswiki::Func::getPubUrlPath($oldWeb, $oldTopic);

    foreach my $meta (@$metas) {
        my $targetPath = ($meta->web() eq $newWeb && $meta->topic() eq $newTopic) ? '%ATTACHURLPATH%' : "%PUBURLPATH%/$newWeb/$newTopic";
        my $storedText = $meta->text();
        my $text = $storedText;
        my %boundaries = (
            '[' => ']',
            '"' => '"',
            "'" => "'",
        );
        while (my ($left, $right) = each %boundaries) {
            $text =~ s/(?<=\Q$left\E)(?:\%ATTACHURL(?:PATH)?\%|\%PUBURL(?:PATH)?\%\/\Q$oldWeb\/$oldTopic\E|\Q$oldPubUrl\E|\Q$oldPubUrlPath\E)\/\Q$oldAttachment\E(?=\Q$right\E|[?#])/$targetPath\/$newAttachment/gm;
        }

        if($storedText ne $text) {
            $meta->text($text);
            $meta->save( minor => 1 );
        }
    }
}

sub updateAttachmentMoveMetadata {
    my ($topicObject, $options) = @_;
    foreach my $attachmentMove ($topicObject->find('WORKFLOWATTACHMENTMOVE')) {
        if($attachmentMove->{value} =~ s#^\Q$options->{oldWeb}\E/\Q$options->{oldTopic}\E$#$options->{newWeb}/$options->{newTopic}#) {
            $topicObject->putKeyed('WORKFLOWATTACHMENTMOVE', $attachmentMove);
        }
    }
}

### copied/modified from Foswiki::UI::Rename
sub _updateReferringTopics {
    my ( $session, $refs, $fn, $options ) = @_;

    my $renderer = $session->renderer;
    require Foswiki::Render;

    $options->{pre} = 1;    # process lines in PRE blocks

    foreach my $item (@$refs) {
        my ( $itemWeb, $itemTopic ) = split( /\./, $item, 2 );

        if ( $session->topicExists( $itemWeb, $itemTopic ) ) {
            my $topicObject =
              Foswiki::Meta->load( $session, $itemWeb, $itemTopic );
            unless ( $topicObject->haveAccess('CHANGE') ) {
                $session->logger->log( 'warning',
                    "Access to CHANGE $itemWeb.$itemTopic is denied: "
                      . $Foswiki::Meta::reason );
                next;
            }
            my $unChangedSerial = Foswiki::Serialise::serialise($topicObject, 'Embedded');
            $options->{inWeb} = $itemWeb;
            my $text =
              $renderer->forEachLine( $topicObject->text(), $fn, $options );
            $options->{inMeta} = 1;
            $topicObject->forEachSelectedValue(
                qw/^(FIELD|FORM|PREFERENCE|TOPICPARENT)$/,
                undef, $fn, $options );
            $options->{inMeta} = 0;
            updateAttachmentMoveMetadata($topicObject, $options);
            $topicObject->text($text);
            $topicObject->save( minor => 1 ) unless Foswiki::Serialise::serialise($topicObject, 'Embedded') eq $unChangedSerial;
        }
    }
}

1;
