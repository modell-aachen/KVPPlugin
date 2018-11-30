<template>
    <div class="grid-x">
        <div class="KVPPlugin TransitionMenu cell">
            <vue-collapsible-frame
                :item="item"
                :collapsible="false"
                class="cell">
                <div class="grid-x align-justify">
                    <div class="cell medium-6 transitionmenu-left">
                        <div class="grid-x">
                            <div class="cell small-4 kvp-label">{{ $t('current_state') }}</div>
                            <div class="cell small-8">
                                {{ message }}
                            </div>
                        </div>
                        <vue-spacer
                            factor-vertical="2"
                            factor-horizontal="full"/>
                        <div
                            v-if="showCompare"
                            class="grid-x">
                            <div
                                class="cell small-4 kvp-label">
                                {{ $t('compare') }}
                            </div>
                            <div
                                class="cell small-8">
                                <a :href="compare_href">
                                    {{ $t('compare_approved') }}
                                </a>
                            </div>
                            <vue-spacer
                                factor-vertical="2"
                                factor-horizontal="full"/>
                        </div>
                        <div
                            v-if="actions.length">
                            <div
                                class="grid-x">
                                <div
                                    class="cell small-4 kvp-label">
                                    {{ $t('remark') }}
                                </div>
                                <div
                                    class="cell small-8">
                                    <textarea
                                        v-model="remark"
                                        name="message"
                                        rows="3"/>
                                </div>
                            </div>
                            <vue-spacer
                                factor-vertical="2"
                                factor-horizontal="full"/>
                            <div
                                class="grid-x">
                                <div
                                    class="cell small-4 kvp-label">
                                    {{ $t('next_step') }}
                                </div>
                                <div
                                    class="cell small-8">
                                    <vue-select
                                        v-model="selectedActionValue"
                                        :initial-options="actionsList"
                                        :sort-slot-options="false"/>
                                </div>
                            </div>
                            <div class="grid-x">
                                <div class="cell">
                                    <vue-text-block
                                        v-if="!selectedAction.proponent"
                                        is-full-width
                                        type="secondary">
                                        {{ $t('proponent_already_signed') }}
                                    </vue-text-block>
                                    <vue-spacer
                                        v-if="!selectedAction.proponent && offerDeleteComments"
                                        factor-vertical="2"/>
                                    <vue-check-item
                                        v-if="offerDeleteComments"
                                        v-model="deleteComments"
                                        checked>{{ $t('delete_comments') }}
                                    </vue-check-item>
                                    <vue-spacer
                                        v-if="!selectedAction.proponent || offerDeleteComments"
                                        factor-vertical="2"/>
                                    <vue-spacer factor-vertical="1"/>
                                    <vue-button
                                        :title="$t('submit_change_status')"
                                        :on-click="doTransition"
                                        :is-disabled="!selectedAction.proponent"
                                        type="primary" />
                                </div>
                            </div>
                        </div>
                    </div>
                    <div class="cell xxlarge-6 large-6 medium-6">
                        <workflow-history />
                    </div>
                </div>
            </vue-collapsible-frame>
        </div>
    </div>
</template>

<script>
import WorkflowHistory from "./WorkflowHistory.vue";

export default {
    name: "TransitionMenu",
    i18nextNamespace: "KVPPlugin",
    components: {
        WorkflowHistory,
    },
    props: {
        web: {
            required: true,
            type: String,
        },
        topic: {
            required: true,
            type: String,
        },
        origin: {
            required: true,
            type: String,
        },
        current_state: {
            required: true,
            type: String,
        },
        current_state_display: {
            required: true,
            type: String,
        },
        message: {
            required: true,
            type: String,
        },
        actions: {
            required: true,
            type: Array,
        },
        validation_key: {
            type: String,
            default: undefined,
        },
        submit_callback: {
            required: true,
            type: Function,
        },
    },
    data: function() {
        return {
            item: {
                label: this.$t("cip_header"),
                id: 1,
            },
            isHistoryListLoading: false,
            remark: "",
            selectedActionValue: [],
            deleteComments: false,
        };
    },
    computed: {
        offerDeleteComments() {
            return this.selectedAction.allow_delete_comments || this.selectedAction.suggest_delete_comments;
        },
        selectedAction() {
            if(this.selectedActionValue[0]) {
                return this.actions[this.selectedActionValue[0].value];
            }
        },
        actionsList() {
            return this.actions.map( (action, index) => {
                return {
                    label: this.decodeNonAlnumFilter(action.label),
                    value: index,
                };
            });
        },
        showCompare() {
            if (this.isOrigin) {
                return false;
            }
            let compareUrl = this.$foswiki.getScriptUrlPath("compare");
            let location = new String(window.location); // window.location does not provide indexOf and the likes
            if (location.indexOf(compareUrl) > 0) {
                return false;
            }
            return true;
        },
        compare_href() {
            return this.$foswiki.getScriptUrlPath(
                "compare",
                this.web,
                this.topic,
                { external: this.web + "/" + this.origin, allowtransition: 1 }
            );
        },
        isOrigin() {
            return this.origin === this.topic;
        },
    },
    watch: {
        selectedAction(newAction) {
            this.deleteComments = newAction.suggest_delete_comments ? true : false;
        }
    },
    created: function() {
        this.selectedActionValue.push(this.actionsList[0]);
    },
    methods: {
        decodeNonAlnumFilter(string) {
            if (!string) {
                return string;
            }
            return string.replace(/&#(\d+);/g, function(match, charCode) {
                return String.fromCharCode(charCode);
            });
        },

        doTransition() {
            let action = this.selectedAction;
            if (
                action.mandatoryNotSatisfied &&
                action.mandatoryNotSatisfied.length
            ) {
                alert(
                    this.$t("missing_mandatory") +
                        "\n" +
                        action.mandatoryNotSatisfied.join("\n")
                );
                return;
            }
            let options = {
                validation_key: this.validation_key,
                web: this.web,
                topic: this.topic,
                message: this.remark,
                action: action.action,
                actionDisplayname: action.label,
                deleteComments: this.deleteComments ? 1 : 0,
                currentState: this.current_state,
                currentStateDisplayname: this.current_state_display,
            };
            if (action.warning) {
                this.$showAlert({
                    title: this.$t("note"),
                    text: action.warning,
                    type: "confirm",
                    confirmButtonText: this.$t("ok"),
                    cancelButtonText: this.$t("cancel"),
                })
                    .then(() => {
                        this.submit_callback(options);
                    })
                    .catch(this.$showAlert.noop);
            } else {
                this.submit_callback(options);
            }
        },
    },
};
</script>

<style lang="scss">
.KVPPlugin.TransitionMenu {
    .kvp-label {
        font-weight: 600;
    }
    .ma-splitbutton {
        a.button {
            font-size: 14px;
        }
    }
    .transitionmenu-left {
        padding-right: 48px;
    }
    .transitionmenu-load-more {
        margin-left: 16px;
    }
    .transitionmenu-header {
        margin-top: 0;
        margin-left: 16px;
        margin-bottom: 16px;
    }
}
</style>

