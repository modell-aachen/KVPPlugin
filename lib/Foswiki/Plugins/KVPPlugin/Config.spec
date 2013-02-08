# ---+ Extensions
# ---++ KVPPlugin

# **STRING**
# Welcher Suffix soll an das Topic gehangen werden?
$Foswiki::cfg{Extensions}{KVPPlugin}{suffix} = 'TALK';

# **STRING**
# Alle Topicnamen die diese Regex matchen werden vom Workflow ausgenommen ('   Set WORKFLOW =').
$Foswiki::cfg{Extensions}{KVPPlugin}{except} = '^(WikiGroups|WikiUsers|WebChanges|WebCreateNewTopic|SolrSearch|WebSearch|WebTopicList|WebPreferences|SitePreferences|WebAtom|WebNotify|WebIndex|WebStatistics)$';

# **PERL**
# Falls GETWORKFLOWROW für ein Topic ohne Workflow aufgerufen wird, werden diese Werte benutzt.
# Die Voreinstellung ist auf den ModacSkin abgestimmt.
$Foswiki::cfg{Extensions}{KVPPlugin}{uncontrolledRow} = {'lefttab' => 'Info Page', 'righttab' => 'Old Discussion', 'approved' => 1, 'message' => 'This topic is not under any workflow.'};

# **BOOLEAN**
# Ist diese Option deaktiviert, *muss* eine NEW-Transition durchgef&uuml;hrt werden, wenn eine neue Seite angelegt wird.
$Foswiki::cfg{Extensions}{KVPPlugin}{NoNewRequired} = 0;

# **BOOLEAN**
# Detailierte Logs f&uuml;r Emails aktivieren.
$Foswiki::cfg{Extensions}{KVPPlugin}{MonitorMails} = 0;

# **BOOLEAN**
# Beim indizieren pr&uuml;fen, ob mit Aufgabe betreuter User existiert.
$Foswiki::cfg{Extensions}{KVPPlugin}{MonitorTasked} = 1;

# **STRING**
# Sprache f&uuml;r Maketext in KVP-Mails.
# Bei leerem String wird die Sprache des Browsers verwendet.
$Foswiki::cfg{Extensions}{KVPPlugin}{MailLanguage} = '';
