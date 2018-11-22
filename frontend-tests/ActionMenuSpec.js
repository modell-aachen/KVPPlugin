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
                allow_delete_comments: null,
                suggest_delete_comments: null,
                mandatoryNotSatisfied: null,
            },
        ],
    };
    beforeEach(() => {
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
        wrapper.vm.doTransition(0);
        expect(window.alert).toHaveBeenCalled();
        expect(spy).not.toHaveBeenCalled();
    });
    it("calls the callback, if all mandatory fields are satisfied", () => {
        wrapper.vm.doTransition(1);
        expect(window.alert).not.toHaveBeenCalled();
        expect(spy).toHaveBeenCalled();
    });
});
