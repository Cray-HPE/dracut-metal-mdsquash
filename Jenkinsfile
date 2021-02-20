@Library("dst-shared@master") _
rpmBuild (
    githubPushRepo: "Cray-HPE/dracut-metal-mdsquash",
    githubPushBranches: "release/.*|main",
    masterBranch: "main",
    specfile: "dracut-metal-mdsquash.spec",
    channel: "metal-ci-alerts",
    product: "csm",
    target_node: "ncn",
    fanout_params: ["sle15sp2"],
    slack_notify: ["", "", "false", "false", "true", "true"]
)
