const module = {
    namespaced: true,
    state: {
        status: '',
        origin: '',
        selectedTransition: {},
        possibleTransitions: [],
    },
    mutations: {
        setMetadata(state, {status, origin, possibleTransitions}) {
            state.status = status;
            state.origin = origin;
            state.possibleTransitions = possibleTransitions;
            state.selectedTransition = possibleTransitions[0];
        },
        setSelectedTransition(state, selectedTransition) {
            state.selectedTransition = selectedTransition;
        },
    },
    getters: {
    },
};

export default module;
