import { DefaultNotificationItem } from "discourse/widgets/default-notification-item";
import I18n from "I18n";
import { createWidgetFrom } from "discourse/widgets/widget";
import getURL from "discourse-common/lib/get-url";
import { iconNode } from "discourse-common/lib/icon-library";

createWidgetFrom(DefaultNotificationItem, "admin-problems-notification-item", {
  text() {
    return I18n.t("notifications.admin_problems");
  },

  url() {
    return getURL("/admin");
  },

  icon() {
    return iconNode("gift");
  },
});
