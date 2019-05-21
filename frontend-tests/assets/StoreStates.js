const StatusState = {
    status: "DRAFT",
    message: "This document is a draft.",
    displayName: "Draft",
};

const WorkflowMetadataState = {
    status: "DRAFT",
    origin: "Einkauf",
    possibleTransitions: [
        {
            action: "Request approval",
            proponent: 1,
            label: "Request approval",
            allowDeleteComments: null,
            mandatoryNotSatisfied: ["TopitTitle"],
            remark: 1,
            suggestDeleteComments: null,
        },
        {
            suggestDeleteComments: null,
            remark: null,
            label: "Discard draft",
            mandatoryNotSatisfied: null,
            allowDeleteComments: null,
            action: "Discard draft",
            proponent: 1,
        },
    ],
};

export {StatusState, WorkflowMetadataState};
