const StatusState = {
    status: "DRAFT",
    message: "This document is a draft.",
    displayName: "Draft"
};

const WorkflowMetadataState = {
    status: "DRAFT",
    origin: "Einkauf",
    possibleTransitions: [
        {
            action: "Request approval",
            proponent: 1,
            label: "Request approval",
            allow_delete_comments: null,
            mandatoryNotSatisfied: ["TopitTitle"],
            remark: 1,
            suggest_delete_comments: null
        },
        {
            suggest_delete_comments: null,
            remark: null,
            label: "Discard draft",
            mandatoryNotSatisfied: null,
            allow_delete_comments: null,
            action: "Discard draft",
            proponent: 1
        }
    ]
};

export {StatusState, WorkflowMetadataState};
