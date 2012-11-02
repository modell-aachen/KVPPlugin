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
        var remark = document.getElementById("KVPRemark");
        var selection = WORKFLOW.getSelection();
        if(selection === undefined) return;
        if(remark != null) {
            if(WORKFLOW.remarkOption.indexOf(','+selection+',') > -1) {
                remark.style.display = 'block';
            } else {
                remark.style.display = 'none';
            }
        }
        var box = document.getElementById("WORKFLOWchkbox");
        if (box === undefined || box === null) return;
        if(WORKFLOW.allowOption.indexOf(','+selection+',') > -1) {
            box.style.display = 'inline';
            document.getElementById('WORKFLOWchkboxbox').checked = false;
        } else if (WORKFLOW.suggestOption.indexOf(','+selection+',') > -1) {
            box.style.display = 'inline';
            document.getElementById('WORKFLOWchkboxbox').checked = true;
        } else {
            box.style.display = 'none';
        }
    }
    $('select').change(WORKFLOW.showCheckBox);
    WORKFLOW.showCheckBox();
});
