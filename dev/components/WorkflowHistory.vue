<template>
    <div>
        <div class="transitionmenu-header">
            <vue-header3>
                {{ $t('history') }}
            </vue-header3>
            <vue-check-item
                v-model="showTransitionsOnly"
                class="show-transitions-only-checkbox">
                {{ $t('history_list_show_transitions_only') }}
            </vue-check-item>
        </div>
        <vue-history-list
            :data="displayDataList"
            :is-loading="isHistoryListLoading" />
        <a
            v-show="hasMoreTransitionEntries && !isHistoryListLoading"
            class="transitionmenu-load-more"
            href="#"
            @click.prevent="loadMore()">
            {{ $t('load_older_entries') }}
        </a>
    </div>
</template>

<script>
export default {
    i18nextNamespace: "KVPPlugin",

    data: function() {
        return {
            isHistoryListLoading: false,
            historyEntries: [],
            pageSize: 5,
            hasMoreTransitionEntries: false,
            lastVersion: undefined,
            showTransitionsOnly: true,
            icons: {
                BACK: "fa-arrow-circle-left ma-failure-color",
                DISCARDED: "fa-times-circle ma-failure-color",
                ACCEPTED: "fa-check-circle ma-success-color",
                REQUESTED: "fa-question-circle ma-warning-color",
                ADDED: "fa-plus-circle ma-success-color",
                DEFAULT: "fa-circle",
            },
        };
    },
    computed: {
        displayDataList() {
            if (!this.historyEntries) {
                return;
            }
            const displayList = this.historyEntries.map(item => {
                if (!item.icon) {
                    item.icon = "DEFAULT";
                }
                let action = this.$t("action_text", [
                    item.previousState,
                    item.state,
                ]);
                if (item.type === "save") {
                    action = this.$t("history_list_save_entry", [item.state]);
                }
                if (this.isCreationHistoryEntry(item)) {
                    item.icon = "ADDED";
                    action = "";
                }
                return {
                    actor: item.leavingStateUser,
                    date: this.$moment(item.time).format("D.MM.YYYY, H:mm"),
                    action,
                    comment: item.remark,
                    icon: this.icons[item.icon],
                    description: item.description,
                    key: item.version,
                    actionUrl: item.url,
                };
            });
            return displayList;
        },
    },
    watch: {
        showTransitionsOnly() {
            this.lastVersion = undefined;
            this.historyEntries = [];
            this.getHistoryData();
        },
    },
    async created() {
        this.getHistoryData();
    },
    methods: {
        async getHistoryData() {
            this.isHistoryListLoading = true;
            try {
                let result = await this.getRemoteData();
                this.historyEntries = this.historyEntries.concat(
                    result.historyEntries
                );
                this.hasMoreTransitionEntries = result.hasMoreEntries;
            } catch (error) {
                this.$showAlert({
                    type: "error",
                    title: this.$t("error"),
                    text: this.$t("loading_error"),
                    confirmButtonText: this.$t("ok"),
                });
                window.console.log(error);
            }
            this.isHistoryListLoading = false;
        },
        loadMore() {
            this.lastVersion = this.historyEntries[
                this.historyEntries.length - 1
            ].version;
            this.getHistoryData();
        },
        async getRemoteData() {
            const parameters = {
                topic:
                    Vue.foswiki.getPreference("WEB") +
                    "." +
                    Vue.foswiki.getPreference("TOPIC"),
                startFromVersion: this.lastVersion,
                size: this.pageSize,
                onlyIncludeTransitions: this.showTransitionsOnly,
            };
            return await this.performHistoryRequest(parameters);
        },
        async performHistoryRequest(parameters) {
            const ajaxReqObj = {
                dataType: "json",
                traditional: true,
                type: "GET",
                data: parameters,
                url: Vue.foswiki.getScriptUrl("rest", "KVPPlugin", "history"),
            };
            return await $.ajax(ajaxReqObj);
        },
        async loadHistory(index) {
            await this.openHistoryTopic(this.displayDataList[index].key);
        },
        isCreationHistoryEntry(entry) {
            return entry.type === 'transition' && (entry.isCreation || entry.isFork);
        }
    },
};
</script>
