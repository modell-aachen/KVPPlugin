<template>
    <div class="grid-x">
        <div class="KVPPlugin TransitionMenue cell">
            <vue-collapsible-frame
                :item="item"
                :collapsible="false"
                class="cell"
            >
                <div class="cell xxlarge-4 large-6 medium-6">
                    <div class="grid-x">
                        <div class="cell small-4 kvp-label">{{ $t('current_state') }}</div>
                        <div class="cell small-8">{{ current_state_display }}</div>
                    </div>
                    <div
                        v-if="!isOrigin"
                        class="grid-x"
                    >
                        <vue-spacer
                            factor-vertical="2"
                            factor-horizontal="full"
                        />
                        <div
                            class="cell small-4 kvp-label"
                        >
                            {{ $t('compare') }}
                        </div>
                        <div
                            class="cell small-8"
                        >
                            <vue-button
                                :title="$t('compare_approved')"
                                :href="compare_href"
                            />
                        </div>
                    </div>
                    <vue-spacer
                        v-else
                        factor-vertical="2"
                        factor-horizontal="full"
                    />
                    <div
                        v-if="actions.length"
                    >
                        <div
                            class="grid-x"
                        >
                            <div
                                class="cell small-4 kvp-label"
                            >
                                {{ $t('remark') }}
                            </div>
                            <div
                                class="cell small-8"
                            >
                                <textarea
                                    name="message"
                                    rows="3"
                                />
                            </div>
                        </div>
                        <vue-spacer
                            factor-vertical="2"
                            factor-horizontal="full"
                        />
                        <div
                            class="grid-x"
                        >
                            <div
                                class="cell small-4 kvp-label"
                            >
                                {{ $t('next_step') }}
                            </div>
                            <div
                                class="cell small-8"
                            >
                                <vue-button
                                    v-if="actions.length == 1"
                                    :title="actions[0].label"
                                    type="primary"
                                    @click.native="doTransition(0)"
                                />
                                <splitbutton
                                    v-else
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
                </div>
            </vue-collapsible-frame>
        </div>
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
                item: {
                    label: this.$t('cip_header'),
                    id: 1,
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
.KVPPlugin.TransitionMenue{
    .kvp-label{
        font-weight: 600;
    }
    .ma-splitbutton{
        a.button{
            font-size: 14px;
        }
    }
}
</style>

