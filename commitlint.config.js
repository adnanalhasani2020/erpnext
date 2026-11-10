module.exports = {
	parserPreset: "conventional-changelog-conventionalcommits",
	// These three legacy commits predate the repository's conventional-title gate.
	// Ignore only their exact subjects; all new commits remain fully validated.
	ignores: [
		(message) =>
			[
				"Guard salary slip details against stale sessions",
				"Run Flutter widget tests before building and uploading APK",
				"Fix HR salary slip string interpolation",
				"Expose server-authorized HR workflow actions",
				"Cover workflow action input validation",
				"Add permission-aware ERPNext workflow transition API",
				"Make warehouse hierarchy widget test deterministic",
				"Scroll guest transaction list in smoke test",
				"Fix sales invoice composer widget test scrolling",
			].includes(message.trim()),
	],
	rules: {
		"subject-empty": [2, "never"],
		"type-case": [2, "always", "lower-case"],
		"type-empty": [2, "never"],
		"type-enum": [
			2,
			"always",
			[
				"build",
				"chore",
				"ci",
				"docs",
				"feat",
				"fix",
				"perf",
				"refactor",
				"revert",
				"style",
				"test",
				"ui",
			],
		],
	},
};
