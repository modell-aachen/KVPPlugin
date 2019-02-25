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
                            <div
                                class="cell small-8"
                                data-test="kvpCurrentState">
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
                                        v-model="selectedActionForSelect"
                                        :initial-options="actionsList"
                                        :sort-slot-options="false"/>
                                    <slot name="transition-info" />
                                </div>
                            </div>
                            <div class="grid-x">
                                <div class="cell">
                                    <vue-text-block
                                        v-if="selectedAction && !selectedAction.proponent"
                                        is-full-width
                                        type="secondary">
                                        {{ $t('proponent_already_signed') }}
                                    </vue-text-block>
                                    <vue-spacer
                                        v-if="selectedAction && !selectedAction.proponent && offerDeleteComments"
                                        factor-vertical="2"/>
                                    <vue-check-item
                                        v-if="offerDeleteComments"
                                        v-model="deleteComments"
                                        checked>{{ $t('delete_comments') }}
                                    </vue-check-item>
                                    <vue-spacer
                                        v-if="(selectedAction && !selectedAction.proponent) || offerDeleteComments"
                                        factor-vertical="2"/>
                                    <vue-spacer factor-vertical="1"/>
                                    <vue-button
                                        :title="$t('submit_change_status')"
                                        :on-click="doTransition"
                                        :is-disabled="selectedAction && !selectedAction.proponent"
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
import { mapState } from 'vuex';

export default {
    name: "TransitionMenu",
    i18nextNamespace: "KVPPlugin",
    components: {
        WorkflowHistory,
    },
    data: function() {
        return {
            item: {
                label: this.$t("cip_header"),
                id: 1,
            },
            isHistoryListLoading: false,
            remark: "",
            deleteComments: false,
            isTransitioning: false,
        };
    },
    computed: {
        ...mapState({
            web: state => state.Qwiki.Document.web,
            topic: state => state.Qwiki.Document.topic,
            origin: state => state.Qwiki.Document.WorkflowMetadata.origin,
            current_state: state => state.Qwiki.Document.WorkflowMetadata.status,
            actions: state => state.Qwiki.Document.WorkflowMetadata.possibleTransitions,
        }),
        current_state_object() {
            return this.$store.state.Qwiki.Workflow.states[this.current_state];
        },

        current_state_display() {
            return this.current_state_object.displayName;
        },
        message() {
            return this.current_state_object.message;
        },
        offerDeleteComments() {
            if(this.selectedAction) {
                return this.selectedAction.allow_delete_comments || this.selectedAction.suggest_delete_comments;
            }
        },
        selectedActionForSelect: {
            get() {
                return [this.selectedAction || ""];
            },
            set(newValue) {
                this.selectedAction = newValue[0];
            },
        },
        selectedAction: {
            set(newSelectedTransitionFromSelect) {
                const newSelectedTransition = this.actions[newSelectedTransitionFromSelect.value];
                if(newSelectedTransition) {
                    this.$store.commit('Qwiki/Document/WorkflowMetadata/setSelectedTransition', newSelectedTransition);
                }
            },
            get() {
                return this.$store.state.Qwiki.Document.WorkflowMetadata.selectedTransition;
            },
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
    methods: {
        decodeNonAlnumFilter(string) {
            if (!string) {
                return string;
            }
            return string.replace(/&#(\d+);/g, function(match, charCode) {
                return String.fromCharCode(charCode);
            });
        },

        async doTransition() {
            if(this.isTransitioning) {
                window.console.log('Transition already in progress -> cancelling request');
                return;
            }
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
            if (action.warning) {
                this.$showAlert({
                    title: this.$t("note"),
                    text: action.warning,
                    type: "confirm",
                    confirmButtonText: this.$t("ok"),
                    cancelButtonText: this.$t("cancel"),
                })
                    .then(async () => {
                        await this.requestTransitionChange();
                    })
                    .catch(this.$showAlert.noop);
            } else {
                await this.requestTransitionChange();
            }
        },
        async requestTransitionChange() {
            this.isTransitioning = true;
            let options = {
                web: this.web,
                topic: this.web+'.'+this.topic,
                message: this.remark,
                WORKFLOWACTION: this.selectedAction.action,
                actionDisplayname: this.selectedAction.label,
                remove_comments: this.deleteComments ? 1 : 0,
                WORKFLOWSTATE: this.current_state,
                current_state_displayname: this.current_state_display,
                validation_key: await this.$getStrikeOneToken(),
                json: 1,
            };
            try {
                let result = await this.performChangeStateRequest(options);
                if(result.redirect) {
                    this.redirect(result.redirect);
                }
            } catch (error) {
                this.$showAlert({
                    type: "error",
                    title: this.$t("error"),
                    text: this.$t("loading_error"),
                    confirmButtonText: this.$t("ok"),
                });
                window.console.log(error);
            }
        },
        async performChangeStateRequest(options) {
            const ajaxOptions = {
                url: Vue.foswiki.getScriptUrl("rest", "KVPPlugin", "changeState"),
                data: options,
                type: "POST",
                traditional: true,
                dataType: 'json',
            };
            return await $.ajax(ajaxOptions);
        },
        redirect(target) {
            window.location.href = target;
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

