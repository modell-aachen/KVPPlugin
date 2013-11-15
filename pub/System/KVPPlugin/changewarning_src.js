jQuery(function($) {
    function confirmation(e) {
        if(!confirm(foswiki.getMetaTag('TEXT_KVPDiscussionMessage').replace(/\\\\n/g, "\n"))) {
            e.stopPropagation();
            e.preventDefault();
        }
    }
    $('a.modacChanging').click(confirmation);
    $('form.modacChanging').submit(function() {return confirm(KVPMessage);});
});
