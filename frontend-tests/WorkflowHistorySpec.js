import WorkflowHistory from "../dev/components/WorkflowHistory.vue";
import TestCase from "VueJSPlugin/unit-test-dist/frontend-unit-test-library";

describe("The WorkflowHistory component", () => {
    let wrapper;
    let getRemoteDataSub;
    const ajaxReturn = {
        hasMoreEntries: 1,
        historyEntries: [
            {
                previousState: "Prüfung",
                time: "Thu, 04 Oct 2018 09:39:40 +0200",
                description: null,
                state: "Gelöscht",
                version: "12",
                isFork: 0,
                isCreation: 0,
                icon: null,
                leavingStateUser: "Internal Admin User",
                remark: "nnnnnnn",
                type: "transition",
            },
            {
                time: "Thu, 04 Oct 2018 09:26:14 +0200",
                previousState: "Neu",
                description: null,
                isCreation: 0,
                icon: null,
                leavingStateUser: "Internal Admin User",
                isFork: 0,
                state: "Prüfung",
                version: "11",
                remark: "",
                type: "transition",
            },
            {
                remark: "",
                state: "Neu",
                version: "10",
                isFork: 0,
                isCreation: 0,
                icon: null,
                leavingStateUser: "Internal Admin User",
                description: null,
                previousState: "Gelöscht",
                time: "Thu, 04 Oct 2018 09:26:06 +0200",
                type: "transition",
            },
            {
                remark: "",
                state: "Gelöscht",
                version: "9",
                isFork: 0,
                isCreation: 0,
                leavingStateUser: "Internal Admin User",
                icon: null,
                description: null,
                previousState: "Prüfung",
                time: "Thu, 04 Oct 2018 09:26:01 +0200",
                type: "transition",
            },
            {
                previousState: "Neu",
                time: "Tue, 02 Oct 2018 16:59:09 +0200",
                description: null,
                state: "Prüfung",
                version: "8",
                isFork: 0,
                leavingStateUser: "Internal Admin User",
                isCreation: 1,
                icon: null,
                remark: "",
                type: "transition",
            },
        ],
    };

    beforeEach(() => {
        getRemoteDataSub = jasmine.createSpy().and.callFake(async () => {
            return ajaxReturn;
        });
        wrapper = TestCase.mount(WorkflowHistory, {
            methods: {
                performHistoryRequest: getRemoteDataSub,
            },
            stubs: ["vue-history-list"],
            sync: false,
        });
    });
    it("transition is mapped correctly", async () => {
        await wrapper.vm.getHistoryData();
        const mappedTransition = {
            actor: "Internal Admin User",
            date: "4.10.2018, 9:26",
            action: "action_text",
            comment: "",
            icon: "fa-circle",
            description: null,
            key: "11",
            actionUrl: undefined,
        };
        expect(wrapper.vm.displayDataList[1]).toEqual(mappedTransition);
    });
    it("creation transition is mapped correctly", async () => {
        await wrapper.vm.getHistoryData();
        expect(wrapper.vm.displayDataList[4].action).toEqual("");
        expect(wrapper.vm.displayDataList[4].icon).toEqual(
            "fa-plus-circle ma-success-color"
        );
    });
    it("upadtes last version to get correct new page", async () => {
        expect(wrapper.vm.lastVersion).toEqual(undefined);
        await Vue.nextTick();
        await wrapper.vm.loadMore();
        expect(wrapper.vm.lastVersion).toEqual("8");
    });

    it("only shows transition history entries by default", async () => {
        const value = wrapper.find(".show-transitions-only-checkbox input")
            .element.checked;

        expect(value).toBe(true);
    });

    it("loads history elements after creation", async () => {
        expect(getRemoteDataSub).toHaveBeenCalled();
    });

    it("reloads elements when switching 'show only transitions' toggle", async () => {
        wrapper.find(".show-transitions-only-checkbox input").setChecked(false);
        await Vue.nextTick();

        expect(
            getRemoteDataSub.calls.mostRecent().args[0].onlyIncludeTransitions
        ).toBe(false);
    });
});
