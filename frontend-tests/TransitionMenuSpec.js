import TransitionMenu from '../dev/components/TransitionMenu.vue';
import TestCase from 'VueJSPlugin/unit-test-dist/frontend-unit-test-library';

describe("The TransitionMenu component", () => {
    let wrapper;
    const spy = jasmine.createSpy('callback');
    const getRemoteDataSub = async () => {
        return ajaxReturn;
    };
    const propsData = {
        "web": "DummyWeb",
        "topic": "DummyTopic",
        "origin": "DummyTopic",
        "current_state": "DummyState",
        "current_state_display": "Dummy state",
        "message": "State",
        "submit_callback": spy,
        "actions": [
            {
                "proponent" : 1,
                "action" : "some mandatory",
                "warning" : null,
                "suggest_delete_comments" : null,
                "allow_delete_comments" : null,
                "mandatoryNotSatisfied" : ['Some field'],
                "remark" : null
            },
            {
                "remark" : null,
                "warning" : null,
                "proponent" : 1,
                "action" : "no mandatory",
                "allow_delete_comments" : null,
                "suggest_delete_comments" : null,
                "mandatoryNotSatisfied" : null
            }
        ]
    };
    const ajaxReturn = {
        "hasMoreEntries":1,
        "transitions":[
            {
                "previousState":"Prüfung",
                "time":"Thu, 04 Oct 2018 09:39:40 +0200",
                "description":null,
                "state":"Gelöscht",
                "version":"12",
                "isFork":0,
                "isCreation":0,
                "icon":null,
                "leavingStateUser":"Internal Admin User",
                "remark":"nnnnnnn"
            }, {
                "time":"Thu, 04 Oct 2018 09:26:14 +0200",
                "previousState":"Neu",
                "description":null,
                "isCreation":0,
                "icon":null,
                "leavingStateUser":"Internal Admin User",
                "isFork":0,
                "state":"Prüfung",
                "version":"11",
                "remark":""
            }, {
                "remark":"",
                "state":"Neu",
                "version":"10",
                "isFork":0,
                "isCreation":0,
                "icon":null,
                "leavingStateUser":"Internal Admin User",
                "description":null,
                "previousState":"Gelöscht",
                "time":"Thu, 04 Oct 2018 09:26:06 +0200"
            }, {
                "remark":"",
                "state":"Gelöscht",
                "version":"9",
                "isFork":0,
                "isCreation":0,
                "leavingStateUser":"Internal Admin User",
                "icon":null,
                "description":null,
                "previousState":"Prüfung",
                "time":"Thu, 04 Oct 2018 09:26:01 +0200"
            }, {
                "previousState":"Neu",
                "time":"Tue, 02 Oct 2018 16:59:09 +0200",
                "description":null,
                "state":"Prüfung",
                "version":"8",
                "isFork":0,
                "leavingStateUser":"Internal Admin User",
                "isCreation":1,
                "icon":null,
                "remark":""
            }
        ]
    };
    describe("action menu", () => {
        beforeEach(() => {
            wrapper = TestCase.mount(TransitionMenu, {
                propsData,
                methods: {
                    getRemoteData: getRemoteDataSub,
                },
            });
            spyOn(window, 'alert');
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
    describe("history menu", () => {
        beforeEach(() => {
            wrapper = TestCase.mount(TransitionMenu, {
                propsData,
                methods: {
                    getRemoteData: getRemoteDataSub,
                },
            });
        });
        it("transition is mapped correctly", async () => {
            await wrapper.vm.getTransitionData();
            const mappedTransition = {
                actor: 'Internal Admin User',
                date: '4.10.2018, 9:26',
                action: 'action_text',
                comment: '',
                icon: 'fa-circle',
                description: null,
                key: '11'
            };
            expect(wrapper.vm.displayDataList[1]).toEqual(mappedTransition);
        });
        it("creation transition is mapped correctly", async () => {
            await wrapper.vm.getTransitionData();
            expect(wrapper.vm.displayDataList[4].action).toEqual('');
            expect(wrapper.vm.displayDataList[4].icon).toEqual('fa-plus-circle ma-success-color');
        });
        it("upadtes last version to get correct new page", async () => {
            expect(wrapper.vm.lastVersion).toEqual(undefined);
            await wrapper.vm.getTransitionData();
            expect(wrapper.vm.lastVersion).toEqual('8');
        });
    });
});
