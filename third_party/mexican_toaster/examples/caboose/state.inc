// State machine for Mexican Toaster lifecycle
//
// States:  kCold -> kThawed -> kFrozen -> kPersisted
// Actions: thaw, freeze, persist, discard
//
// Transition table:
//   kCold      + thaw    -> kThawed
//   kThawed    + freeze  -> kFrozen
//   kThawed    + persist -> kPersisted
//   kThawed    + discard -> kCold
//   kFrozen    + thaw    -> kThawed   (resume)
//   kFrozen    + persist -> kPersisted
//   kFrozen    + discard -> kCold
//   kPersisted + thaw    -> kThawed   (fresh cycle on new binary)

enum ToasterState {
  kCold,
  kThawed,
  kFrozen,
  kPersisted,
};

enum ToasterAction {
  kActionThaw,
  kActionFreeze,
  kActionPersist,
  kActionDiscard,
};

static const char *ToasterStateName(enum ToasterState s) {
  switch (s) {
    case kCold:      return "cold";
    case kThawed:    return "thawed";
    case kFrozen:    return "frozen";
    case kPersisted: return "persisted";
    default:         return "unknown";
  }
}

static const char *ToasterActionName(enum ToasterAction a) {
  switch (a) {
    case kActionThaw:    return "thaw";
    case kActionFreeze:  return "freeze";
    case kActionPersist: return "persist";
    case kActionDiscard: return "discard";
    default:             return "unknown";
  }
}

// Transition table: [from][action] = to, or -1 for invalid
// Rows: kCold=0, kThawed=1, kFrozen=2, kPersisted=3
// Cols: kActionThaw=0, kActionFreeze=1, kActionPersist=2, kActionDiscard=3
static const int kTransitionTable[4][4] = {
  /* kCold      */ { kThawed,  -1,       -1,         -1     },
  /* kThawed    */ { -1,       kFrozen,  kPersisted, kCold  },
  /* kFrozen    */ { kThawed,  -1,       kPersisted, kCold  },
  /* kPersisted */ { kThawed,  -1,       -1,         -1     },
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
