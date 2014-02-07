jQuery(function($) {
    var confirmation = function(e) {
        return confirm(foswiki.getMetaTag('TEXT_KVPDiscussionMessage').replace(/\\\\?n/g, "\n"));
    };
    window.kvpDiscussionConfirmation = confirmation;
    $('a.modacChanging').click(confirmation);
    $('form.modacChanging').submit(function() {return confirm(KVPMessage);});
});
