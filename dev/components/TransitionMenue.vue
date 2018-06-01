<template>
    <div class="KVPPlugin TransitionMenue">
        <vue-collapsible-dad-item
            :item="dadDummy.item"
            :index="dadDummy.index"
            :last-opened-item-id="dadDummy.item.id"
        >
            <div class="grid-x">
                <div class="cell small-2">{{ $t('current_state') }}</div>
                <div class="cell small-4">{{ current_state_display }}</div>
            </div>
            <div
                v-if="!isOrigin"
                class="grid-x"
            >
                <div
                    class="cell small-2"
                >
                    {{ $t('compare') }}
                </div>
                <div
                    class="cell small-4"
                >
                    <vue-button
                        :title="$t('compare_approved')"
                        :href="compare_href"
                    />
                </div>
            </div>
            <div
                v-if="actions.length"
            >
                <vue-header ruler/>
                <div
                    class="grid-x"
                >
                    <div
                        class="cell small-2"
                    >
                        {{ $t('remark') }}
                    </div>
                    <div
                        class="cell small-4"
                    >
                        <textarea
                            name="message"
                            rows="3"
                        />
                    </div>
                </div>
                <div
                    class="grid-x"
                >
                    <div
                        class="cell small-2"
                    >
                        {{ $t('next_step') }}
                    </div>
                    <div
                        class="cell small-4"
                    >
                        <button
                            v-if="actions.length == 1"
                            :title="actions[0].label"
                            @click="doTransition(0)"
                        />
                        <splitbutton
                            :on-main-button-click="function(){doTransition(0);}"
                            :main-button-title="actions[0].label"
                            :dropdown-button-title="$t('more')"
                        >
                            <template slot="dropdown-content">
                                <li
                                    v-for="(item, index) in actions.slice(1)"
                                    :key="index"
                                    @click="doTransition(index + 1)"
                                >
                                    <a>{{ item.label }}</a>
                                </li>
                            </template>
                        </splitbutton>
                    </div>
                </div>
            </div>
        </vue-collapsible-dad-item>
    </div>
</template>

<script>
export default {
name: 'TransitionMenue',
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
        actions: {
            required: true,
            type: Array,
        },
        validation_key: {
            required: false,
            type: String,
            default: undefined,
        },
        submit_callback: {
            required: true,
            type: Function,
                default: () => window.console.log('internal error: missing submit_callback'),
        },
    },
    data: function() {
        return {
            dadDummy: {
                item: {
                    label: this.$t('cip_header'),
                    id: 1,
                },
                index: 0,
            },
            use_action: undefined,
        };
    },
    computed: {
        compare_href: function() {
            return this.$foswiki.getScriptUrlPath('compare', this.web, this.topic, { external: this.web + '/' + this.origin });
        },
        isOrigin: function() {
            return this.origin === this.topic;

        },
    },
    methods: {
        doTransition: function(actionNr) {
            let action = this.actions[actionNr];
            this.submit_callback(this.validation_key, this.web, this.topic, action.action, this.current_state);
        }
    },
}
</script>

<style lang="scss">
.KVPPlugin.TransitionMenue {
    .vddl-handle {
        display: none;
    }
}
</style>

