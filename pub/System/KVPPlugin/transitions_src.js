jQuery(function($) {
    var json = $('script.KVPPlugin_WORKFLOW');
    if(!json.length) {
        window.console && console.log('Could not find json in script.KVPPLUGIN_WORKFLOW');
        return;
    }
    var WORKFLOW = window.JSON.parse(json.html()).WORKFLOW;
    window.WORKFLOW = WORKFLOW; // XXX: legacy

    WORKFLOW.getSelection = function($form) {
        if($form === undefined || $form.length === 0) {
            $form = $('.KVPTransitionForm:first');
        }
        var menu = $form.find('#WORKFLOWmenu');
        var selection = menu.val();
        if(selection === undefined) {
            selection = $form.find('[name="WORKFLOWACTION"]').val();
        }
        return selection;
    }

    WORKFLOW.confirm = function($form) {
        var warning;
        if(WORKFLOW.w) warning = WORKFLOW.w[WORKFLOW.getSelection($form)];
        if(!warning || warning == '' || confirm(warning) === true) {
            // get block-message
            var message = foswiki.getMetaTag('TEXT_BLOCKUI_KVP');
            if(message === undefined || message === "") {
                message = foswiki.getMetaTag('TEXT_BLOCKUI');
            }
            // block
            if (message === undefined || message === "") {
                var options;
                if(window.foswiki && window.foswiki.ModacSkin && window.foswiki.ModacSkin.getBlockDefaultOptions) {
                    options = foswiki.ModacSkin.getBlockDefaultOptions();
                }
                $('#KVPTransitions').block(options);
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
        return WORKFLOW.confirm($(this));
    });
    WORKFLOW.showCheckBox();
});
