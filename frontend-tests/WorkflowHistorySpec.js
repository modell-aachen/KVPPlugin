import WorkflowHistory from "../dev/components/WorkflowHistory";
import {historyAjaxData} from './assets/HistoryListAjaxData';
import {buildEnvironment} from './KVPEnvironmentBuilder';

describe("The WorkflowHistory component", () => {
    let workflowHistory;
    let getRemoteDataStub;

    beforeEach(() => {
        getRemoteDataStub = jasmine.createSpy().and.callFake(async () => {
            return historyAjaxData;
        });

        workflowHistory = buildEnvironment(WorkflowHistory, {
            methods: {
                performHistoryRequest: getRemoteDataStub,
            },
            stubs: ["vue-history-list"],
            sync: false,
        });
    });
    it("transition is mapped correctly", async () => {
        await workflowHistory.vm.getHistoryData();
        const mappedTransition = {
            actor: "Internal Admin User",
            date: "4.10.2018, 9:26",
            action: "action_text",
            comment: "",
            icon: "fa-circle",
            description: null,
            key: "11",
            actionUrl: "http://localhost",
        };
        expect(workflowHistory.vm.displayDataList[1]).toEqual(mappedTransition);
    });
    it("creation transition is mapped correctly", async () => {
        await workflowHistory.vm.getHistoryData();
        expect(workflowHistory.vm.displayDataList[4].action).toEqual("");
        expect(workflowHistory.vm.displayDataList[4].icon).toEqual(
            "fa-plus-circle ma-success-color"
        );
    });
    it("upadtes last version to get correct new page", async () => {
        expect(workflowHistory.vm.lastVersion).toEqual(undefined);
        await Vue.nextTick();
        await workflowHistory.vm.loadMore();
        expect(workflowHistory.vm.lastVersion).toEqual("8");
    });

    it("only shows transition history entries by default", async () => {
        const value = workflowHistory.find(".show-transitions-only-checkbox input")
            .element.checked;

        expect(value).toBe(true);
    });

    it("loads history elements after creation", async () => {
        expect(getRemoteDataStub).toHaveBeenCalled();
    });

    it("reloads elements when switching 'show only transitions' toggle", async () => {
        workflowHistory.find(".show-transitions-only-checkbox input").setChecked(false);
        await Vue.nextTick();

        expect(
            getRemoteDataStub.calls.mostRecent().args[0].onlyIncludeTransitions
        ).toBe(false);
    });
});
