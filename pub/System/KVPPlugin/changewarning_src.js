jQuery(function($) {
    var confirmation = function(e) {
        var msg = foswiki.getMetaTag('TEXT_KVPDiscussionMessage').replace(/\\\\?n/g, "\n");
        if(msg) return confirm(foswiki.getMetaTag('TEXT_KVPDiscussionMessage').replace(/\\\\?n/g, "\n"));
    };
    window.kvpDiscussionConfirmation = confirmation;
    $('a.modacChanging').click(confirmation);
    $('form.modacChanging').submit(confirmation);
});
