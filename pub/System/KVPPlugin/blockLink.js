jQuery(function($){
    function disable(e) {
        $(e.target).parent().block({message: ''});
    };
    $('.kvpForkLink').click(disable);
});
