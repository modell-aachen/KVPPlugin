import TransitionMenue from '../components/TransitionMenue.vue';

import translationsEn from '../translations/en.json';
import translationsDe from '../translations/de.json';

jQuery(function($) {
    Vue.addTranslation('en', 'KVPPlugin', translationsEn);
    Vue.addTranslation('de', 'KVPPlugin', translationsDe);

    Vue.component(TransitionMenue.name, TransitionMenue);

    /**
     * This callback will create a form with the action data and submit it.
     * This is done outside of vue, so StrikeOne will not mess with vue's
     * stuff.
     */
    let submitAction = function({validation_key, web, topic, action, currentState, actionDisplayname, currentStateDisplayname}) {
        let $form = $(`
            <form
                ref="transitionForm"
                method="post"
                style="display:none"
            >
                <input
                    type="hidden"
                    name="WORKFLOWSTATE"
                >
                <input
                    type="hidden"
                    name="topic"
                >
                <input
                    type="hidden"
                    name="WORKFLOWACTION"
                >
                <input
                    type="hidden"
                    name="action_displayname"
                >
                <input
                    type="hidden"
                    name="current_state_displayname"
                >
            </form>`);
        $form.attr('action', foswiki.getScriptUrl('rest', 'KVPPlugin', 'changeState'));
        $form.find('[name="WORKFLOWACTION"]').val(action);
        $form.find('[name="WORKFLOWSTATE"]').val(currentState);
        $form.find('[name="action_displayname"]').val(actionDisplayname);
        $form.find('[name="current_state_displayname"]').val(currentStateDisplayname);
        $form.find('[name="topic"]').val(web + '.' + topic);
        $('body').append($form);
        if(window.StrikeOne && validation_key) {
            $('<input type="hidden" name="validation_key">').val(validation_key).appendTo($form);
            window.StrikeOne.submit($form.get(0));
        }
        $form.submit();
    };

    $('div.KVPPlugin.vue-transitions').each(function() {
        let data;
        let $transitionDiv = $(this);
        try {
            let json = $transitionDiv.find(".json").text();
            data = JSON.parse(json);
        } catch(e) {
            window.console && window.console.log('Could not initialize KVPPlugin vue transition', e);
            return;
        }
        data['submit_callback'] = submitAction;
        data['validation_key'] = $transitionDiv.find('[name="validation_key"]').val();
        let keys = Object.keys(data).filter(key => /^[a-z_-]+$/.test(key)); // do not allow v-on:...
        let props = Array.map(keys, key => `:${key}="${key}"`);
        let $transitionMenue = $(`<transition-menue ${props.join(' ')}></transition-menue>`);
        //copy attrs for vue-client tokens
        let attributes = $transitionDiv.prop("attributes");
        $.each(attributes, function() {
            if( this.name !== 'class') {
                $transitionMenue.attr(this.name, this.value);
            }
        });

        let id = 'kvp' + foswiki.getUniqueID();
        $transitionMenue.attr('id', id);
        $transitionDiv.replaceWith($transitionMenue);

        Vue.instantiateEach( '#' + id, { data } );
    });
});

