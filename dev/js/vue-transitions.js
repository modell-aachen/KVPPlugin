import TransitionMenu from '../components/TransitionMenu';
import MetadataStore from './MetadataStore';
import WorkflowStore from './WorkflowStore';

import translationsEn from '../translations/en.json';
import translationsDe from '../translations/de.json';

jQuery(function() {
    Vue.addTranslation('en', 'KVPPlugin', translationsEn);
    Vue.addTranslation('de', 'KVPPlugin', translationsDe);

    Vue.component(TransitionMenu.name, TransitionMenu);

    Vue.registerStoreModule(['Qwiki', 'Document', 'WorkflowMetadata'], MetadataStore);
    Vue.registerStoreModule(['Qwiki', 'Workflow'], WorkflowStore);
    Vue.instantiateEach( '.workflow-vue');
});
