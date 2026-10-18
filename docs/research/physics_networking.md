# Research: networked physics props (2026-10-18)

Question (Zachary): is there an existing physics or networking system that matches what we want for
props (grab, carry, throw, push, heavy lifts with helpers, co-op over Steam) that we could use or build on?

## What we looked at

| Option | What it is | Fits us? |
|---|---|---|
| **Jolt** (already in use) | Godot 4's physics engine, switched on in this project. | Yes. It does the physics itself; the question is only how to share it over the network. |
| **netfox** (foxssake/netfox, MIT) | Godot add-on for rollback netcode (players predict, server corrects). | Not for props. Its maintainers say rollback doesn't work with RigidBody3D, because Godot physics isn't deterministic and can't re-simulate several times per frame. They recommend state syncing for rigid bodies, which is what we do. |
| **Rapier physics** (appsinacup/godot-rapier-physics) | A replacement physics engine with a deterministic (same input = same result on every PC) build. | Possible later, but a big switch. Determinism would allow lockstep or rollback, but only the slower build is deterministic across different PCs, and the rest of Godot isn't deterministic. Not worth it for a co-op game among friends. |
| **R.E.P.O.** (Semiwork, Unity + Photon) | The closest game to ours: co-op physics carrying of loot. | Its exact method isn't public. Photon's own blog only says physics sync was its biggest problem. |
| **Photon / Coherence ownership transfer** (Unity world) | The common pattern for grabbable objects: the player who touches an object becomes its owner and simulates it; ownership goes back when it's released and has stopped moving; other PCs' copies are kinematic. | This is exactly our approach B. |

## Conclusion

There is no ready-made Godot add-on that does physics props over the network better than what we
have. The usual, proven method for this kind of game is what we built: the host runs props, ownership
moves to the player who grabs or pushes one, it returns when it settles, and other PCs show frozen
copies that glide between snapshots. We'll keep our own system and improve it with what we learned.

## Ideas to adopt from the research
- Jolt can fling nearby bodies when a rigid body is teleported by setting its transform. When we
  move a prop instantly (ownership start, key-object respawn), also zero its velocities, and if
  flinging shows up in playtests, do the move inside `_integrate_forces()` instead.
- Ask before taking over a prop that's already ours (we already skip that).
- Keep ownership changes broadcast to every PC (we do) and validated on the host (we do).

## Round 2 (2026-10-18): Half-Life 2 / Source

**How Half-Life 2 holds props** (Valve's Source SDK, `weapon_physcannon.cpp`, `CGrabController`):
- Each physics tick it drives the object toward a target position and angle with "shadow control"
  (the velocity that gets it there now, capped at 1000 units/s and 3600 degrees/s), not a spring.
- While held, the object's mass is set to 1 kg and angular damping to 10; both are restored on release.
- The target angle is the angle the object had at pickup, kept relative to the player (the +use pickup
  ignores pitch). The target distance grows with the object's size, is shortened by a trace when a wall
  is in front, and pitch is limited to 75 degrees.
- It drops the object when the error gets too big (about 12 units), when the player stands on it, or
  when it can no longer move. Contact with heavy objects reduces how fast it can turn.
- Throwing uses the eye direction times a force scaled by mass, plus random spin. A normal release caps
  speed (about 1.5 x run speed) and spin (720 degrees/s), so you can't fling things by spinning.

**How Source shows other players' objects smoothly** (Valve Developer Wiki):
- Clients draw entities slightly in the past and blend between two snapshots (default 100 ms; the
  modern advice is two update intervals). If updates are late, they extrapolate for up to 0.25 s.

**Why there was still jitter** (Godot docs and forum): physics runs 60 times a second, but a 144 Hz
screen draws more frames than that, so moving things only change on some frames. Godot's physics
interpolation fixes this; a first-person camera should follow the body's interpolated position in
`_process` and take mouse look directly.

All of this is now in physics_props (and the player camera).

Also adopted: Glenn Fiedler's "ownership sequence" idea from his Networked Physics articles (each prop's
owner number goes up on every hand-over, and updates with an old number are ignored), and claiming objects
just before contact (an extension of the knock-on ownership idea). Source: https://gafferongames.com/categories/networked-physics/

More sources:
- Source SDK 2013, weapon_physcannon.cpp: https://github.com/ValveSoftware/source-sdk-2013
- Valve wiki, Player pickup: https://developer.valvesoftware.com/wiki/Player_pickup
- Valve wiki, Source Multiplayer Networking: https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking
- Valve wiki, Interpolation: https://developer.valvesoftware.com/wiki/Interpolation
- Godot docs, advanced physics interpolation: https://docs.godotengine.org/en/4.x/tutorials/physics/interpolation/advanced_physics_interpolation.html
- Godot forum, Camera3D interpolation jitter fix: https://forum.godotengine.org/t/camera3d-interpolation-jitter-fix/129269

## Sources
- netfox and rigid bodies: https://github.com/foxssake/netfox/discussions/272
- netfox repository: https://github.com/foxssake/netfox
- Rapier determinism: https://godot.rapier.rs/docs/documentation/determinism
- R.E.P.O. and Photon: https://blog.photonengine.com/r-e-p-o-multiplayer-success-powered-by-photon/
- Photon ownership "Takeover": https://www.vrwiki.cs.brown.edu/unity/multiplayer-vr-development-in-unity/photon-pun-2/basic-photon-guide
- Photon rigid body ownership discussion: https://forum.photonengine.com/discussion/comment/29548/
- Coherence authority transfer for physics: https://docs.coherence.io/0.10/learning-coherence/first-steps-tutorial/2-physics-authority-transfer
- Godot forum, authority for interactable objects: https://forum.godotengine.org/t/how-to-change-multiplayer-authority-for-interactable-objects/132685
- Godot forum, Jolt flinging when moving rigid bodies: https://forum.godotengine.org/t/not-sure-how-to-properly-move-rigidbody3ds-without-being-flinged-in-jolt-physics/116053
