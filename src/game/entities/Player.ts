import { Scene, GameObjects, Types } from "phaser";
import { Constants } from "../utils/Constants.ts";
import { FontUtils } from "../utils/FontUtils.ts";

export class Player {
    private scene: Scene;
    private sprite: GameObjects.Sprite;
    private nameText: GameObjects.Text;
    private cursors: Types.Input.Keyboard.CursorKeys;
    private wasd: Record<string, Phaser.Input.Keyboard.Key>;
    private shiftKey: Phaser.Input.Keyboard.Key; // Add shift key
    private currentAnimation: string = "idle-down";
    private lastSentPosition: { x: number; y: number } | null = null;
    private lastSentAnimation: string | null = null;
    private username: string;
    private movementSmoothing: number = 0.2; // Controls movement smoothness (lower = smoother)

    constructor(
        scene: Scene,
        x: number,
        y: number,
        cursors: Types.Input.Keyboard.CursorKeys,
        wasd: Record<string, Phaser.Input.Keyboard.Key>
    ) {
        this.scene = scene;
        this.cursors = cursors;
        this.wasd = wasd;
        this.username = scene.registry.get("username") || "Player";

        // Register shift key for running
        this.shiftKey = scene.input.keyboard!.addKey("SHIFT");

        // Create player sprite
        this.sprite = scene.add.sprite(x, y, "character");
        this.sprite.setScale(0.3); // Scale up the character to be more visible

        // Create animations
        this.createAnimations();

        // Set initial animation
        this.sprite.anims.play("idle-down");

        // Add physics to player
        scene.physics.add.existing(this.sprite);

        if (this.sprite.body) {
            const body = this.sprite.body as Phaser.Physics.Arcade.Body;
            body.setCollideWorldBounds(true);
            body.setSize(240, 240);
            body.setOffset(300, 480);
            body.setDamping(true);
            body.setDrag(0.85, 0.85);
        }
        // Create username text with proper font loading
        this.nameText = scene.add
            .text(x, y + 350, this.username, {
                fontFamily: FontUtils.getPlayerNameFont(),
                fontSize: Constants.PLAYER_NAME_SIZE,
                color: Constants.PLAYER_NAME_COLOR,
                align: "center",
                backgroundColor: Constants.PLAYER_NAME_BACKGROUND,
                padding: Constants.PLAYER_NAME_PADDING,
            })
            .setOrigin(0.5, 3);

        // Ensure font is loaded and refresh the text if needed
        FontUtils.ensureFontLoaded(
            "Tickerbit",
            Constants.PLAYER_NAME_SIZE
        ).then(() => {
            this.nameText.setStyle({
                fontFamily: FontUtils.getPlayerNameFont(),
                fontSize: Constants.PLAYER_NAME_SIZE,
                color: Constants.PLAYER_NAME_COLOR,
            });
        });
    }

    update(deltaFactor: number = 1): void {
        this.handleMovement(deltaFactor);
        this.updateNamePosition();
    }

    private handleMovement(deltaFactor: number): void {
        // Calculate movement
        let dx = 0;
        let dy = 0;
        const isRunning = this.shiftKey.isDown;
        const speed = isRunning
            ? Constants.PLAYER_SPEED * 1.6 * deltaFactor // 60% faster when running
            : Constants.PLAYER_SPEED * deltaFactor;

        // Check both arrow keys and WASD
        if (this.cursors.left?.isDown || this.wasd.left?.isDown) {
            dx = -speed;
            if (isRunning) {
                this.sprite.anims.play("run-left", true);
                this.currentAnimation = "run-left";
            } else {
                this.sprite.anims.play("walk-left", true);
                this.currentAnimation = "walk-left";
            }
        } else if (this.cursors.right?.isDown || this.wasd.right?.isDown) {
            dx = speed;
            if (isRunning) {
                this.sprite.anims.play("run-right", true);
                this.currentAnimation = "run-right";
            } else {
                this.sprite.anims.play("walk-right", true);
                this.currentAnimation = "walk-right";
            }
        }

        if (this.cursors.up?.isDown || this.wasd.up?.isDown) {
            dy = -speed;
            if (dx === 0) {
                if (isRunning) {
                    this.sprite.anims.play("run-up", true);
                    this.currentAnimation = "run-up";
                } else {
                    this.sprite.anims.play("walk-up", true);
                    this.currentAnimation = "walk-up";
                }
            }
        } else if (this.cursors.down?.isDown || this.wasd.down?.isDown) {
            dy = speed;
            if (dx === 0) {
                if (isRunning) {
                    this.sprite.anims.play("run-down", true);
                    this.currentAnimation = "run-down";
                } else {
                    this.sprite.anims.play("walk-down", true);
                    this.currentAnimation = "walk-down";
                }
            }
        }

        // Handle idle animations
        if (dx === 0 && dy === 0) {
            // Get current animation key
            const currentAnim = this.sprite.anims.currentAnim;
            if (currentAnim) {
                const direction = currentAnim.key.split("-")[1];
                this.sprite.anims.play("idle-" + direction, true);
                this.currentAnimation = "idle-" + direction;
            }
        }

        // Normalize diagonal movement
        if (dx !== 0 && dy !== 0) {
            dx *= Math.SQRT1_2;
            dy *= Math.SQRT1_2;
        }

        // Set player velocity using physics body
        if (this.sprite.body) {
            // Direct velocity setting for smoother movement
            (this.sprite.body as Phaser.Physics.Arcade.Body).setVelocity(
                dx,
                dy
            );

            // Apply integer pixel positions to reduce flickering
            if (dx === 0 && dy === 0) {
                // Only snap position when not moving to prevent jitter
                this.sprite.x = Math.round(this.sprite.x);
                this.sprite.y = Math.round(this.sprite.y);

                // Also stop the body velocity completely when not moving
                (this.sprite.body as Phaser.Physics.Arcade.Body).setVelocity(
                    0,
                    0
                );
            }
        }
    }

    private createAnimations(): void {
        const { anims } = this.scene;

        // Only create animations if they don't exist already
        if (anims.exists("idle-down")) return;

        // C2.png has 4x4 grid (16 frames total)
        // Row 1 (frames 0-3): Down-facing characters (S key)
        // Row 2 (frames 4-7): Left-facing characters (A key)
        // Row 3 (frames 8-11): Right-facing characters (D key)
        // Row 4 (frames 12-15): Up-facing characters (W key)
        // Columns 1-2: Idle positions
        // Columns 3-4: Running positions

        // Down animations (Row 1: frames 0-3) - All use idle frames
        anims.create({
            key: "idle-down",
            frames: anims.generateFrameNumbers("character", { frames: [0, 1] }),
            frameRate: 2,
            repeat: -1,
        });
        anims.create({
            key: "walk-down",
            frames: anims.generateFrameNumbers("character", { frames: [0, 1] }),
            frameRate: 2,
            repeat: -1,
        });
        anims.create({
            key: "run-down",
            frames: anims.generateFrameNumbers("character", { frames: [0, 1] }),
            frameRate: 2,
            repeat: -1,
        });

        // Left animations (Row 2: frames 4-7) - All use idle frames
        anims.create({
            key: "idle-left",
            frames: anims.generateFrameNumbers("character", { frames: [4, 5] }),
            frameRate: 2,
            repeat: -1,
        });
        anims.create({
            key: "walk-left",
            frames: anims.generateFrameNumbers("character", { frames: [4, 5] }),
            frameRate: 2,
            repeat: -1,
        });
        anims.create({
            key: "run-left",
            frames: anims.generateFrameNumbers("character", { frames: [4, 5] }),
            frameRate: 2,
            repeat: -1,
        });

        // Right animations (Row 3: frames 8-11) - All use idle frames
        anims.create({
            key: "idle-right",
            frames: anims.generateFrameNumbers("character", { frames: [8, 9] }),
            frameRate: 2,
            repeat: -1,
        });
        anims.create({
            key: "walk-right",
            frames: anims.generateFrameNumbers("character", { frames: [8, 9] }),
            frameRate: 2,
            repeat: -1,
        });
        anims.create({
            key: "run-right",
            frames: anims.generateFrameNumbers("character", { frames: [8, 9] }),
            frameRate: 2,
            repeat: -1,
        });

        // Up animations (Row 4: frames 12-15) - All use idle frames
        anims.create({
            key: "idle-up",
            frames: anims.generateFrameNumbers("character", {
                frames: [12, 13],
            }),
            frameRate: 2,
            repeat: -1,
        });
        anims.create({
            key: "walk-up",
            frames: anims.generateFrameNumbers("character", {
                frames: [12, 13],
            }),
            frameRate: 2,
            repeat: -1,
        });
        anims.create({
            key: "run-up",
            frames: anims.generateFrameNumbers("character", {
                frames: [12, 13],
            }),
            frameRate: 2,
            repeat: -1,
        });
    }

    private updateNamePosition(): void {
        this.nameText.x = this.sprite.x;
        this.nameText.y = this.sprite.y - 50;
    }

    // Getters and utility methods
    getSprite(): GameObjects.Sprite {
        return this.sprite;
    }

    getNameText(): GameObjects.Text {
        return this.nameText;
    }

    getPosition(): { x: number; y: number } {
        return { x: this.sprite.x, y: this.sprite.y };
    }

    getCurrentAnimation(): string | null {
        return this.currentAnimation || null;
    }

    setLastSentPosition(position: { x: number; y: number }): void {
        this.lastSentPosition = position;
    }

    getLastSentPosition(): { x: number; y: number } | null {
        return this.lastSentPosition;
    }

    setLastSentAnimation(animation: string): void {
        this.lastSentAnimation = animation;
    }

    getLastSentAnimation(): string | null {
        return this.lastSentAnimation;
    }

    getUsername(): string {
        return this.username;
    }
}
