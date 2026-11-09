# Sprite handoff

Branch: ccr-bd57c499-uq5kbg

M01 source checkpoints are committed under art/sprites/burrower_v2. The previous rejected/intermediate direction sheets remain explicitly named candidates. Runtime replacement uses 106 frames: five authored walk families mirrored to eight directions, sixteen turn poses, three six-frame attacks, two ten-frame deaths, twelve emergence frames. Intermediate walk headings use the nearest authored facing. The approved Kestrel layered head/pedestal work is also committed.

Rebuild: python tools/sprites/assemble_burrower_v2.py
Review: open art/previews/m01_full_review.html in a browser.
Test: godot --headless --path godot --script res://tests/monster_sprite_check.gd

Validation: atlas bounds and padding pass; independent review identified and confirmed corrections to corpse ground contact, rear-walk source-row jump and side-death scale. Final follow-up registers death/turn upper-shell landmarks. Remaining art limitations: turntable wrap changes proportions, side-death entry differs vertically from walk; entire state graph has not had live-combat visual approval. Event previews are forced repeats, not actual battle trigger behavior.

GitHub push failed because Git cannot obtain credentials. The portable bundle contains the committed branch and its history. On the other device, copy the bundle then run:

    git clone -b ccr-bd57c499-uq5kbg northgate-sprite-handoff.bundle northgate-game
    cd northgate-game
    git remote set-url origin https://github.com/Aravind-pk/game.git

Or fetch the bundle into an existing clone and check out its branch. Open godot/project.godot in Godot 4.5.1 to reimport the changed textures. Localhost preview addresses on the old device do not transfer.

Other pre-existing uncommitted gameplay/UI/build changes were not committed as part of this sprite task. The bundle only guarantees committed content, not the entire old device working directory.
