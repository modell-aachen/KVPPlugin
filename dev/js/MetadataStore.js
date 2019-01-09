const module = {
    namespaced: true,
    state: {
        status: '',
        origin: '',
        possibleTransitions: [],
    },
    mutations: {
        setMetadata(state, {status, origin, possibleTransitions}) {
            state.status = status;
            state.origin = origin;
            state.possibleTransitions = possibleTransitions;
        },
    },
    getters: {
    },
};

export default module;

