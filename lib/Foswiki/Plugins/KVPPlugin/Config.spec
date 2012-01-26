# ---+ Extensions
# ---++ KVPPlugin

# **STRING**
# Welcher Suffix soll an das Topic gehangen werden?
$Foswiki::cfg{Extensions}{KVPPlugin}{suffix} = 'TALK';

# **STRING**
# Alle Topicnamen die diese Regex matchen werden vom Workflow ausgenommen ('   Set WORKFLOW =').
$Foswiki::cfg{Extensions}{KVPPlugin}{except} = '^WikiGroups$|^WikiUsers$|^WebChanges$|^WebCreateNewTopic$|^SolrSearch$|^WebTopicList$|^WebPreferences$|^SitePreferences$|^WebAtom$|^WebNotify$|WebIndex$|^WebStatistics$';

# **PERL**
# Falls GETWORKFLOWROW für ein Topic ohne Workflow aufgerufen wird, werden diese Werte benutzt.
# Die Voreinstellung ist auf den ModacSkin abgestimmt.
$Foswiki::cfg{Extensions}{KVPPlugin}{uncontrolledRow} = {'stategroup' => 'Infoseite', 'discussionlabel' => 'alte Diskussion', 'istdiskussion' => 0};


