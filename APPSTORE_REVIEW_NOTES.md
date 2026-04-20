# App Store Connect 审核备注（针对 3.1.1 拒审）

> 在 App Store Connect → 此版本 → **App Review Information → Notes（审核备注）** 里粘贴下方英文版。
> 中文版仅供你自己核对内容。

---

## ✅ 本版本针对上次拒审（Guideline 3.1.1）所做的改动

1. **会员页面对已订阅用户也保留可点击按钮**（按钮文案变为「管理订阅 / Manage Subscription」），点击后弹出对话框并跳转到系统订阅管理页面，不再是灰色 disabled 状态。
2. **新增「恢复购买 / Restore Purchases」按钮**，位于会员页底部，所有 iOS 用户始终可见可点。
3. 提供专用测试账号（**非会员**），方便审核员完整体验 IAP 购买流程。

---

## 📝 英文版（直接粘贴到 App Review Information → Notes）

```text
Dear App Review Team,

Thank you for the previous review. We have addressed the 3.1.1 issue:

1. RESTORE PURCHASES
   A "Restore Purchases" button is now ALWAYS visible at the bottom of
   the membership page (Profile tab → Membership / 我的 → 会员中心),
   for every iOS user regardless of subscription status.

2. PURCHASE FLOW IS ALWAYS REACHABLE
   Even when the signed-in account already has an active membership,
   each plan card now shows a "Manage Subscription" button (instead of
   a disabled state) that opens the iOS subscription management page.

3. DEDICATED REVIEWER ACCOUNT (NON-MEMBER)
   To verify the in-app purchase flow end-to-end, please use the
   following non-member test account:

       Email:    <REPLACE_WITH_REVIEWER_EMAIL>
       Password: <REPLACE_WITH_REVIEWER_PASSWORD>

   How to reach the IAP flow:
     a) Launch the app and sign in with the account above.
     b) Tap the "我的 / Profile" tab (rightmost wrench icon at the
        bottom).
     c) Tap "会员中心 / Membership".
     d) Choose any plan (Monthly / Yearly / Lifetime) and tap
        "立即订阅 / Subscribe Now" to trigger the StoreKit purchase
        sheet.
     e) "恢复购买 / Restore Purchases" is at the bottom of the same
        page.

Note: The previous reviewer account was already a Lifetime member,
which is why all plan buttons appeared as "已开通 (Subscribed)" and
the IAP flow looked unreachable. The dedicated non-member account
above resolves this.

Thank you!
```

---

## 🔧 还要做的两件小事

1. 在 App Store Connect 里把「**Demo Account**」字段也填一份非会员账号（不仅是 Notes）。
2. 提交前请在 TestFlight 用**全新 Sandbox Apple ID**亲自走一遍：
   - 进入会员页 → 看到「恢复购买」按钮 ✅
   - 用已是会员的账号进入 → 看到「管理订阅」按钮（非灰色）✅
   - 用未订阅账号点订阅 → 弹出系统购买框 ✅
