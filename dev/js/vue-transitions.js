import TransitionMenu from '../components/TransitionMenu';
import MetadataStore from './MetadataStore';
import WorkflowStore from './WorkflowStore';

import translationsEn from '../translations/en.json';
import translationsDe from '../translations/de.json';

jQuery(function($) {
    Vue.addTranslation('en', 'KVPPlugin', translationsEn);
    Vue.addTranslation('de', 'KVPPlugin', translationsDe);

    Vue.component(TransitionMenu.name, TransitionMenu);

    /**
     * This callback will create a form with the action data and submit it.
     * This is done outside of vue, so StrikeOne will not mess with vue's
     * stuff.
     */
    let submitAction = function({validation_key, web, topic, action, currentState, actionDisplayname, currentStateDisplayname, message, deleteComments}) {
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
                    name="message"
                >
                <input
                    type="hidden"
                    name="remove_comments"
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
        $form.find('[name="message"]').val(message);
        $form.find('[name="remove_comments"]').val(deleteComments);
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
        let $transitionDiv = $(this);
        let data = {
            'submit_callback': submitAction,
            'validation_key': $transitionDiv.find('[name="validation_key"]').val(),
        };
        let keys = Object.keys(data).filter(key => /^[a-z_-]+$/.test(key)); // do not allow v-on:...
        let props = keys.map(key => `:${key}="${key}"`);
        let $transitionMenu = $(`<transition-menu ${props.join(' ')}></transition-menu>`);
        //copy attrs for vue-client tokens
        let attributes = $transitionDiv.prop("attributes");
        $.each(attributes, function() {
            if( this.name !== 'class') {
                $transitionMenu.attr(this.name, this.value);
            }
        });

        let id = 'kvp' + foswiki.getUniqueID();
        $transitionMenu.attr('id', id);
        $transitionDiv.replaceWith($transitionMenu);

        Vue.registerStoreModule(['Qwiki', 'Document', 'WorkflowMetadata'], MetadataStore);
        Vue.registerStoreModule(['Qwiki', 'Workflow'], WorkflowStore);
        Vue.instantiateEach( '#' + id, { data } );
    });
});

