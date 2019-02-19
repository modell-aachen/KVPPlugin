import TestCase from "VueJSPlugin/unit-test-dist/frontend-unit-test-library";
import TransitionMenu from "../dev/components/TransitionMenu.vue";

describe("action menu", () => {
    let wrapper;
    const spy = jasmine.createSpy("callback");
    const getRemoteDataSub = async () => {
        return [];
    };
    const propsData = {
        web: "DummyWeb",
        topic: "DummyTopic",
        origin: "DummyTopic",
        current_state: "DummyState",
        current_state_display: "Dummy state",
        message: "State",
        submit_callback: spy,
        actions: [
            {
                proponent: 1,
                action: "some mandatory",
                label: "some mandatory",
                warning: null,
                suggest_delete_comments: null,
                allow_delete_comments: null,
                mandatoryNotSatisfied: ["Some field"],
                remark: null,
            },
            {
                remark: null,
                warning: null,
                proponent: 1,
                action: "no mandatory",
                label: "no mandatory",
                allow_delete_comments: null,
                suggest_delete_comments: null,
                mandatoryNotSatisfied: null,
            },
        ],
    };
    beforeEach(() => {
        spy.calls.reset();
        wrapper = TestCase.mount(TransitionMenu, {
            propsData,
            methods: {
                getRemoteData: getRemoteDataSub,
            },
            stubs: ['workflow-history'],
        });
        spyOn(window, "alert");
    });
    it("aborts with a warning, if there are unmet mandatory fields", () => {
        wrapper.vm.doTransition();
        expect(window.alert).toHaveBeenCalled();
        expect(spy).not.toHaveBeenCalled();
    });
    it("calls the callback, if all mandatory fields are satisfied", () => {
        wrapper.setData({selectedActionValue: [wrapper.vm.actionsList[1]]});
        wrapper.vm.doTransition();
        expect(window.alert).not.toHaveBeenCalled();
        expect(spy).toHaveBeenCalled();
    });
    it("calls the callback only once", () => {
        spyOn(window.console, 'log');
        wrapper.setData({selectedActionValue: [wrapper.vm.actionsList[1]]});
        wrapper.vm.doTransition();
        wrapper.vm.doTransition();
        expect(spy.calls.count()).toEqual(1);
    });
    it("gives a debug warning when attempting to transition multiple times", () => {
        spyOn(window.console, 'log');
        wrapper.setData({selectedActionValue: [wrapper.vm.actionsList[1]]});
        wrapper.vm.doTransition();
        wrapper.vm.doTransition();
        expect(window.console.log).toHaveBeenCalled();
    });
    it("call action with correct args", () => {
        wrapper.setData({selectedActionValue: [wrapper.vm.actionsList[1]]});
        wrapper.vm.doTransition();
        expect(spy.calls.mostRecent().args[0].action).toEqual(propsData.actions[1].action);
        expect(spy.calls.mostRecent().args[0].deleteComments).toEqual(0);
    });
});
