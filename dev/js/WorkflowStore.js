const module = {
    namespaced: true,
    state: {
        states: {},
    },
    mutations: {
        setStatus(state, {status, message, displayName}) {
            state.states[status] = Object.assign(state.states[status] || {}, {status, message, displayName});
        },
    },
    getters: {
        getState: (state) => (id) => {
            return state.states.find(item => item.name === id);
        },
    },
};

export default module;

