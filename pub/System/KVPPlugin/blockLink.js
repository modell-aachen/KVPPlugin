jQuery(function($){
    function disable(e) {
        var $this = $(this);
        var warning = $this.attr('warning');
        if(warning && !confirm(warning)) return false;
        $(e.target).parent().block({message: ''});
    };
    $('.kvpForkLink').click(disable);
});
