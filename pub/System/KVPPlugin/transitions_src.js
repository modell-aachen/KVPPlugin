jQuery(function($) {
    WORKFLOW.getSelection = function() {
        var menu = $('#WORKFLOWmenu');
        var selection = menu.val();
        if(selection === undefined) {
            menu = $('#WORKFLOWbutton');
            if (menu === undefined) return undefined;
            selection = menu.text().replace(/^\s+|\s+$/g, '');
        }
        return selection;
    }

    WORKFLOW.confirm = function() {
        var warning = WORKFLOW.w[WORKFLOW.getSelection()] || '';
        if(warning == '' || confirm(warning) === true) {
            // get block-message
            var message = foswiki.getMetaTag('TEXT_BLOCKUI_KVP');
            if(message === undefined || message === "") {
                message = foswiki.getMetaTag('TEXT_BLOCKUI');
            }
            // block
            if (message === undefined || message === "") {
                $('#KVPTransitions').block();
            } else {
                $('#KVPTransitions').block( {message: '<h1>'+message+'</h1>', css: {width: 'auto', height: 'auto', backgroundColor: 'black'}} );
            }

            return true;
        } else {
            return false
        }
    }

    WORKFLOW.showCheckBox = function() {
        var menu = $('#WORKFLOWmenu');
        var remark = $('#KVPRemark');
        var selection = WORKFLOW.getSelection();
        if(selection === undefined) return;
        if(remark != null) {
            if(WORKFLOW.remarkOption.indexOf(','+selection+',') > -1) {
                remark.show();
            } else {
                remark.hide();
            }
        }
        var box = $('#WORKFLOWchkbox');
        if (!box.length) return;
        if(WORKFLOW.allowOption.indexOf(','+selection+',') > -1) {
            box.show();
            $('#WORKFLOWchkboxbox').removeAttr('checked');
        } else if (WORKFLOW.suggestOption.indexOf(','+selection+',') > -1) {
            box.show();
            $('#WORKFLOWchkboxbox').attr('checked', 'checked');
        } else {
            $('#WORKFLOWchkboxbox').removeAttr('checked');
            box.hide();
        }
    }
    $('select').change(WORKFLOW.showCheckBox);
    $('.KVPTransitionForm').submit(function(ev) {
        return WORKFLOW.confirm();
    });
    WORKFLOW.showCheckBox();
});
