import {buildEnvironment} from './KVPEnvironmentBuilder';
import TransitionMenu from "../dev/components/TransitionMenu.vue";
import {WorkflowMetadataState} from './assets/StoreStates';

describe("action menu", () => {
    let transitionMenu;
    let changeStateStub;
    let windowLocationStub;

    beforeEach(() => {
        changeStateStub = jasmine.createSpy().and.callFake(async () => {
            return {redirect: 'http://localhost'};
        });
        windowLocationStub = jasmine.createSpy();
        transitionMenu = buildEnvironment(TransitionMenu, {
            stubs: ['workflow-history'],
            methods: {
                performChangeStateRequest: changeStateStub,
                redirect: windowLocationStub,
            },
            sync: false,
        });
        spyOn(window, "alert");
    });
    it("aborts with a warning, if there are unmet mandatory fields", async () => {
        transitionMenu.vm.doTransition();
        expect(window.alert).toHaveBeenCalled();
        expect(changeStateStub).not.toHaveBeenCalled();
    });
    it("calls the callback, if all mandatory fields are satisfied", async () => {
        transitionMenu.vm.$store.commit('Qwiki/Document/WorkflowMetadata/setSelectedTransition', WorkflowMetadataState.possibleTransitions[1]);
        await transitionMenu.vm.doTransition();
        expect(window.alert).not.toHaveBeenCalled();
        expect(changeStateStub).toHaveBeenCalled();
    });
    it("call change transition ajax request with correct args", async () => {
        transitionMenu.setData({selectedActionForSelect: [transitionMenu.vm.actionsList[1]]});
        await transitionMenu.vm.doTransition();
        expect(
            changeStateStub.calls.mostRecent().args[0].WORKFLOWACTION
        ).toEqual('Discard draft');
        expect(
            changeStateStub.calls.mostRecent().args[0].remove_comments
        ).toEqual(0);
    });
});
