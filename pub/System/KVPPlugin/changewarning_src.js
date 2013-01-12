jQuery(function($) {
    function confirmation(e) {
        if(!confirm(foswiki.getMetaTag('TEXT_KVPDiscussionMessage'))) {
            e.stopPropagation();
            e.preventDefault();
        }
    }
    $('a.modacChanging').click(confirmation);
    $('form.modacChanging').submit(function() {return confirm(KVPMessage);});
});
