# Admin Profile Login Layout Fix

The live `admin.kridiyatravel.com/profile.html` page loads `css/staff.css`.
Its sign-in centering rule includes the other access gates, but omits
`#profile-gate`, so the profile login card falls back to the normal page
container flow and sits on the left.

Apply the same gate treatment to `#profile-gate` in the admin site source:

```css
#admin-gate, #doc-gate, #activity-gate, #dashboard-gate, #bookings-gate,
#corporate-gate, #payments-gate, #portals-gate, #staff-gate, #backups-gate,
#accounting-gate, #templates-gate, #handover-gate, #profile-gate {
  min-height: 72vh;
  display: flex;
  align-items: center;
  justify-content: center;
}

#admin-gate[hidden], #doc-gate[hidden], #activity-gate[hidden],
#dashboard-gate[hidden], #bookings-gate[hidden], #corporate-gate[hidden],
#payments-gate[hidden], #portals-gate[hidden], #staff-gate[hidden],
#backups-gate[hidden], #accounting-gate[hidden], #templates-gate[hidden],
#handover-gate[hidden], #profile-gate[hidden] {
  display: none;
}
```

After this is deployed, `profile.html` will center the Staff Tools login card
like the rest of the admin pages.
