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
                        <div
                            v-if="showCompare"
                            class="grid-x">
                            <vue-spacer
                                factor-vertical="2"
                                factor-horizontal="full"/>
                            <div
                                class="cell small-4 kvp-label">
                                {{ $t('compare') }}
                            </div>
                            <div
                                class="cell small-8">
                                <vue-button
                                    :title="$t('compare_approved')"
                                    :href="compare_href"/>
                            </div>
                        </div>
                        <vue-spacer
                            v-else
                            factor-vertical="2"
                            factor-horizontal="full"/>
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
                                    <vue-button
                                        v-if="actions.length == 1"
                                        :title="decodeNonAlnumFilter(actions[0].label)"
                                        type="primary"
                                        @click.native="doTransition(0)"/>
                                    <splitbutton
                                        v-else
                                        :on-main-button-click="function(){doTransition(0);}"
                                        :main-button-title="decodeNonAlnumFilter(actions[0].label)"
                                        :dropdown-button-title="$t('more')">
                                        <template slot="dropdown-content">
                                            <li
                                                v-for="(item, index) in actions.slice(1)"
                                                :key="index"
                                                @click="doTransition(index + 1)">
                                                <a>{{ item.label }}</a>
                                            </li>
                                        </template>
                                    </splitbutton>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div class="cell xxlarge-6 large-6 medium-6">
                        <vue-header3 class="transitionmenu-header">
                            {{ $t('history') }}
                        </vue-header3>
                        <vue-history-list
                            :data="displayDataList"
                            :is-loading="isTransitionsListLoading"
                            @item-clicked="loadHistory" />
                        <a
                            v-show="hasMoreTransitionEntries && !isTransitionsListLoading"
                            class="transitionmenu-load-more"
                            href="#"
                            @click.prevent="loadMore()">
                            {{ $t('load_older_entries') }}
                        </a>
                    </div>
                </div>
            </vue-collapsible-frame>
        </div>
    </div>
</template>

<script>
export default {
    name: 'TransitionMenu',
    i18nextNamespace: 'KVPPlugin',
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
        'current_state': {
            required: true,
            type: String,
        },
        'current_state_display': {
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
                label: this.$t('cip_header'),
                id: 1,
            },
            use_action: undefined,
            isTransitionsListLoading: false,
            remark: '',
            transitions: [],
            pageSize: 5,
            hasMoreTransitionEntries: false,
            lastVersion: undefined,
            icons: {
                'BACK': 'fa-arrow-circle-left ma-failure-color',
                'DISCARDED': 'fa-times-circle ma-failure-color',
                'ACCEPTED':'fa-check-circle ma-success-color',
                'REQUESTED': 'fa-question-circle ma-warning-color',
                'ADDED': 'fa-plus-circle ma-success-color',
                'DEFAULT': 'fa-circle',
            }
        };
    },
    computed: {
        showCompare() {
            if(this.isOrigin) {
                return false;
            }
            let compareUrl = this.$foswiki.getScriptUrlPath('compare');
            let location = new String(window.location); // window.location does not provide indexOf and the likes
            if(location.indexOf(compareUrl) > 0) {
                return false;
            }
            return true;
        },
        compare_href() {
            return this.$foswiki.getScriptUrlPath('compare', this.web, this.topic, { external: this.web + '/' + this.origin, allowtransition: 1 });
        },
        isOrigin() {
            return this.origin === this.topic;

        },
        displayDataList() {
            if(! this.transitions) {
                return;
            }
            const displayList = this.transitions.map((item) => {
                if(!item.icon) {
                    item.icon = 'DEFAULT';
                }
                let action = this.$t('action_text', [item.previousState, item.state]);
                if(item.isCreation || item.isFork) {
                    item.icon = 'ADDED';
                    action = '';
                }
                return {
                    actor: item.leavingStateUser,
                    date: this.$moment(item.time).format("D.MM.YYYY, H:mm"),
                    action,
                    comment: item.remark,
                    icon: this.icons[item.icon],
                    description: item.description,
                    key: item.version,
                };
            });
            return displayList;
        },
    },
    async created() {
        this.getTransitionData();
    },
    methods: {
        loadMore() {
            this.getTransitionData();
        },
        decodeNonAlnumFilter(string) {
            if(! string) {
                return string;
            }
            return string.replace(/&#(\d+);/g, function(match, charCode) {
                return String.fromCharCode(charCode);
            });
        },
        async getTransitionData() {
            this.isTransitionsListLoading = true;
            try{
                let result = await this.getRemoteData();
                this.transitions = this.transitions.concat(result.transitions);
                this.hasMoreTransitionEntries = result.hasMoreEntries;
                this.isTransitionsListLoading = false;
                this.lastVersion = this.transitions[this.transitions.length -1].version;
            } catch(error) {
                this.$showAlert({
                    type: 'error',
                    title: this.$t('error'),
                    text: this.$t('loading_error'),
                    confirmButtonText: this.$t('ok')
                });
                window.console.log(error);
                this.isTransitionsListLoading = false;
            }
        },
        async getRemoteData() {
            const ajaxReqObj = {
                dataType: 'json',
                traditional: true,
                type: "GET",
                data: {
                    topic: Vue.foswiki.getPreference("WEB")+"."+Vue.foswiki.getPreference("TOPIC"),
                    startFromVersion: this.lastVersion,
                    size: this.pageSize,
                },
                url: Vue.foswiki.getScriptUrl("rest", "KVPPlugin", "history"),
            };
            return await $.ajax(ajaxReqObj);
        },
        doTransition(actionNr) {
            let action = this.actions[actionNr];
            if(action.mandatoryNotSatisfied && action.mandatoryNotSatisfied.length) {
                alert(this.$t('missing_mandatory') + '\n' + action.mandatoryNotSatisfied.join('\n'));
                return;
            }
            let options = {
                validation_key: this.validation_key,
                web: this.web,
                topic: this.topic,
                message: this.remark,
                action: action.action,
                actionDisplayname: action.label,
                currentState: this.current_state,
                currentStateDisplayname: this.current_state_display,
            };
            if(action.warning) {
                this.$showAlert({
                    title: this.$t('note'),
                    text: action.warning,
                    type: 'confirm',
                    confirmButtonText: this.$t('ok'),
                    cancelButtonText: this.$t('cancel'),
                }).then(() => {
                    this.submit_callback(options);
                }).catch(this.$showAlert.noop);
            } else {
                this.submit_callback(options);
            }
        },
        async loadHistory(index) {
            await this.openHistoryTopic(this.displayDataList[index].key);
        },
        async openHistoryTopic(revision) {
            const ajaxReqObj = {
                dataType: 'json',
                traditional: true,
                type: "GET",
                data: {
                    topic: Vue.foswiki.getPreference("WEB")+"."+Vue.foswiki.getPreference("TOPIC"),
                    revision: revision,
                },
                url: Vue.foswiki.getScriptUrl("rest", "ModacHelpersPlugin", "loadHistoryVersion"),
            };
            try {
                const result = await $.ajax(ajaxReqObj);
                window.open(result.url, '_blank');
            } catch(e) {
                alert("could not get history link");
            }
            return;
        },
    },
};
</script>

<style lang="scss">
.KVPPlugin.TransitionMenu{
    .kvp-label{
        font-weight: 600;
    }
    .ma-splitbutton{
        a.button{
            font-size: 14px;
        }
    }
    .transitionmenu-left {
        padding-right: 48px;
    }
    .transitionmenu-load-more {
        margin-left: 16px;
    }
    .vue-header.transitionmenu-header{
        margin-top: 0;
        margin-left: 16px;
        margin-bottom: 16px;
    }
}
</style>

