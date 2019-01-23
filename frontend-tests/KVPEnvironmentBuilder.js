import {buildComponent, mount} from "VueJSPlugin/unit-test-dist/frontend-unit-test-library";
import WorkflowMetadataStore from '../dev/js/MetadataStore';
import WorkflowStore from '../dev/js/WorkflowStore';
import {WorkflowMetadataState, StatusState} from './assets/StoreStates';

const buildEnvironment = (component, options = {}) => {
    let vue = buildComponent();
    vue.registerStoreModule(['Qwiki'], {namespaced: true});
    vue.registerStoreModule(['Qwiki', 'Document'], {
        namespaced: true,
        state: {
            web: "DummyWeb",
            topic: "DummyTopic",
        }
    });
    vue.registerStoreModule(['Qwiki', 'Document', 'WorkflowMetadata'], WorkflowMetadataStore);
    vue.registerStoreModule(['Qwiki', 'Workflow'], WorkflowStore);
    vue.Store.commit('Qwiki/Document/WorkflowMetadata/setMetadata', WorkflowMetadataState);
    vue.Store.commit('Qwiki/Workflow/setStatus', StatusState);
    options.localVue = vue;
    return mount(component, options);
};

export {buildEnvironment};
