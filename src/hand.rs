use base::config::keys;
use hbb_common::config;

pub const APP_NAME: &str = "Hand";
const TAILNET_ONLY: &str = "100.64.0.0/10,fd7a:115c:a1e0::/48,127.0.0.1,::1";

pub fn apply_defaults() {
    if let Ok(mut name) = config::APP_NAME.write() {
        *name = APP_NAME.to_owned();
    }
    if let Ok(mut display) = config::DEFAULT_DISPLAY_SETTINGS.write() {
        display.insert(keys::OPTION_VIEW_STYLE.to_owned(), "adaptive".to_owned());
        display.insert(
            keys::OPTION_DISPLAYS_AS_INDIVIDUAL_WINDOWS.to_owned(),
            "Y".to_owned(),
        );
    }
    if let Ok(mut local) = config::DEFAULT_LOCAL_SETTINGS.write() {
        local.insert(
            keys::OPTION_ENABLE_OPEN_NEW_CONNECTIONS_IN_TABS.to_owned(),
            "N".to_owned(),
        );
    }
    if let Ok(mut settings) = config::DEFAULT_SETTINGS.write() {
        settings.insert(keys::OPTION_DIRECT_SERVER.to_owned(), "Y".to_owned());
        settings.insert(keys::OPTION_WHITELIST.to_owned(), TAILNET_ONLY.to_owned());
    }
}
