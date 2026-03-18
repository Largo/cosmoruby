// State machine for Mexican Toaster lifecycle
//
// States:  kCold -> kWarm -> kThawed -> kFrozen -> kPersisted
//          kWarm can also go directly to toast (ephemeral, no state)
//
// Actions: warm, thaw, freeze, persist, discard
//
// Transition table:
//   kCold      + warm    -> kWarm       (prepare environment)
//   kWarm      + thaw    -> kThawed     (switch to disk upper)
//   kWarm      + toast   -> [ephemeral] (chroot + mtsh, no state change)
//   kThawed    + freeze  -> kFrozen
//   kThawed    + persist -> kPersisted
//   kThawed    + discard -> kCold
//   kFrozen    + thaw    -> kThawed     (resume)
//   kFrozen    + persist -> kPersisted
//   kFrozen    + discard -> kCold
//   kPersisted + thaw    -> kThawed     (fresh cycle on new binary)
//   kPersisted + warm    -> kWarm       (fresh warm on persisted binary)

enum ToasterState {
  kCold,
  kWarm,       // NEW: namespaces + overlay ready, tmpfs upper
  kThawed,     // Warm with disk-based upper
  kFrozen,
  kPersisted,
};

enum ToasterAction {
  kActionWarm,    // NEW
  kActionThaw,
  kActionFreeze,
  kActionPersist,
  kActionDiscard,
};

static const char *ToasterStateName(enum ToasterState s) {
  switch (s) {
    case kCold:      return "cold";
    case kWarm:      return "warm";
    case kThawed:    return "thawed";
    case kFrozen:    return "frozen";
    case kPersisted: return "persisted";
    default:         return "unknown";
  }
}

static const char *ToasterActionName(enum ToasterAction a) {
  switch (a) {
    case kActionWarm:    return "warm";
    case kActionThaw:    return "thaw";
    case kActionFreeze:  return "freeze";
    case kActionPersist: return "persist";
    case kActionDiscard: return "discard";
    default:             return "unknown";
  }
}

// Transition table: [from][action] = to, or -1 for invalid
// Rows: kCold=0, kWarm=1, kThawed=2, kFrozen=3, kPersisted=4
// Cols: kActionWarm=0, kActionThaw=1, kActionFreeze=2, kActionPersist=3, kActionDiscard=4
//
// Note: kActionToast is not in this table because toast is ephemeral
// (no state transition). It can be called from kCold or kWarm.
static const int kTransitionTable[5][5] = {
  /* kCold      */ { kWarm,    kThawed,  -1,         -1,         -1     },
  /* kWarm      */ { -1,       kThawed,  -1,         -1,         kCold  },
  /* kThawed    */ { -1,       -1,       kFrozen,    kPersisted, kCold  },
  /* kFrozen    */ { -1,       kThawed,  -1,         kPersisted, kCold  },
  /* kPersisted */ { kWarm,    kThawed,  -1,         -1,         -1     },
};

// Validate and compute a state transition.
// Returns 0 on success (writing *to), or -1 if the transition is invalid.
static int ToasterTransition(enum ToasterState from, enum ToasterAction action,
                             enum ToasterState *to) {
  if ((unsigned)from > kPersisted || (unsigned)action > kActionDiscard)
    return -1;
  int next = kTransitionTable[from][action];
  if (next == -1) {
    fprintf(stderr, "Invalid transition: %s + %s\n",
            ToasterStateName(from), ToasterActionName(action));
    return -1;
  }
  *to = (enum ToasterState)next;
  return 0;
}
