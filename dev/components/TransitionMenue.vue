<template>
    <div class="grid-x">
        <div class="KVPPlugin TransitionMenue cell">
            <vue-collapsible-frame
                :item="item"
                :collapsible="false"
                class="cell">
                <div class="cell xxlarge-4 large-6 medium-6">
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
            default: 'unknown',
        },
        'current_state_display': {
            required: true,
            type: String,
            default: '(unknown state)',
        },
        message: {
            reequired: true,
            type: String,
            default: 'unknown',
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
        showCompare: function() {
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
        compare_href: function() {
            return this.$foswiki.getScriptUrlPath('compare', this.web, this.topic, { external: this.web + '/' + this.origin, allowtransition: 1 });
        },
        isOrigin: function() {
            return this.origin === this.topic;

        },
    },
    methods: {
        decodeNonAlnumFilter: function(string) {
            return string.replace(/&#(\d+);/g, function(match, charCode) {
                return String.fromCharCode(charCode);
            });
        },
        doTransition: function(actionNr) {
            let action = this.actions[actionNr];
            if(action.mandatoryNotSatisfied && action.mandatoryNotSatisfied.length) {
                alert(this.$t('missing_mandatory') + '\n' + action.mandatoryNotSatisfied.join('\n'));
                return;
            }
            let options = {
                validation_key: this.validation_key,
                web: this.web,
                topic: this.topic,
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
        }
    },
};
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

