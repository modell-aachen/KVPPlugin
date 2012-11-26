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
            $('#KVPTransitions').block();
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
                remark.hide();
            } else {
                remark.show();
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
            box.hide();
        }
    }
    $('select').change(WORKFLOW.showCheckBox);
    WORKFLOW.showCheckBox();
});
