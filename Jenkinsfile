// Pipeline to deploy Terraform

def config = [:]

def forceHTTPS() {
    sh 'git config --global url."https://github.com/".insteadOf git@github.com:'
    sh 'git config --global url."https://github.com/".insteadOf ssh://git@github.com/'
    sh 'git config --global url."https://".insteadOf git://'
    sh 'git config --global url."https://".insteadOf ssh://'
}

config.buildBranch = config.buildBranchOverride == null ? (env.CHANGE_TARGET == null ? env.BRANCH_NAME : env.CHANGE_TARGET) : config.buildBranchOverride

pipeline {
    agent any

    triggers {
        issueCommentTrigger('^/ok$')
    }
    
    environment {
 //       GIT_TOKEN = credentials('github')
        TF_HOME = 'terraform'
        TF_IN_AUTOMATION = 'true'
        GIT_ASKPASS = '/tmp/git-askpass.sh'
        TRIGGER = 'OTHER'
        DIRTY_PLAN = 'false'
        TF_STATE_BUCKET = 'db-tsbpoc-terraform-state'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '5'))
    }

    stages {
        stage('Determine what caused the build') {
            when {
                anyOf {
                    changeRequest target: 'main'
                }
            }

            steps {
                script {
                    def commentTrigger = currentBuild.rawBuild.getCause(org.jenkinsci.plugins.pipeline.github.trigger.IssueCommentCause)

                    if (commentTrigger) {
                        if (commentTrigger.comment == '/ok') {
                            TRIGGER = 'COMMENT_OK'
                        } else {
                            echo 'Other comment'
                            TRIGGER = 'COMMENT_OTHER'
                        }
                    } else {
                        TRIGGER = 'OTHER'
                    }
                }
            }
        }

        stage('Create credential helper script') {
            when {
                anyOf {
                    changeRequest target: 'main'
                }
            }

            steps {
                script {
                    forceHTTPS()
                }
            }
        }

        stage('Terraform: Init') {
            when {
                anyOf {
                    changeRequest target: 'main'
                }
            }

            steps {
                script {
                    dir ('terraform') { 
                        sh "terraform init -input=false -backend-config skip_metadata_api_check=true -backend-config encrypt=true -backend-config region=eu-west-2 -backend-config bucket=${env.TF_STATE_BUCKET} -backend-config key=terraform.tfstate -no-color"
                    }
                }
            }
        }

        stage('Terraform: Plan') {
            when {
                anyOf {
                    changeRequest target: 'main'
                }
            }

            steps {
                script {
                    def tf_changes = [
                        "Create": [],
                        "Delete": [],
                        "Update": [],
                        "Replace": [],
                        "Maintain": []
                    ]
                    def pr_comment = ''

                    // Generate Terraform plan
                    dir ('terraform') { 
                        sh "export TF_LOG='DEBUG' && terraform plan -var-file terraform.tfvars -out plan.out -input=false -no-color"
                    }

                    // Export plan as JSON
                    
                    def tf_plan_text = sh (
                        script: "${env.TF_HOME}/terraform show -json plan.out",
                        returnStdout: true
                    ).trim()
                    
                    def tf_plan = readJSON text: tf_plan_text

                    // Hash plan
                    def plan_hash = java.security.MessageDigest.getInstance('sha1').digest(tf_plan.resource_changes.toString().bytes).encodeHex().toString()

                    // Determine whether the plan needs to be applied
                    if (TRIGGER == 'COMMENT_OK') {
                        // Copy hash from S3
                        dir ('terraform') { 
                            sh "aws s3 cp s3://${env.TF_STATE_BUCKET}/${env.CHANGE_ID}.hash plan.hash"
                        }

                        // Read hash
                        dir ('terraform') { 
                            def old_plan_hash = readFile file: 'plan.hash'
                        }

                        // Continue to the next iteration if the hashes match
                        if (plan_hash == old_plan_hash) {
                            return
                        }

                        DIRTY_PLAN = 'true'
                    }

                    // Copy hash to S3
                    dir ('terraform') { 
                        writeFile file: "plan.hash", text: plan_hash
                        sh "aws s3 cp plan.hash s3://${env.TF_STATE_BUCKET}/${env.CHANGE_ID}.hash"
                    }

                    tf_plan.resource_changes.each { change ->
                        if (change.change.actions.contains('update')) {
                            tf_changes["Update"] += change
                        } else if (change.change.actions.contains('create') && change.change.actions.contains('delete')) {
                            tf_changes["Replace"] += change
                        } else if (change.change.actions.contains('create')) {
                            tf_changes["Create"] += change
                        } else if (change.change.actions.contains('delete')) {
                            tf_changes["Delete"] += change
                        } else {
                            tf_changes["Maintain"] += change
                        }
                    }

                    // Continue to the next stage if the plan can be applied
                    if (TRIGGER == 'COMMENT_OK' && DIRTY_PLAN == 'false') {
                        return
                    } else if (DIRTY_PLAN == 'true') {
                        pr_comment += '**The plan has changed. Please review the new plan and re-approve.**\n\n'
                    }

                    // Add PR comment
                    pr_comment += "The following resources will be affected by this deployment:\n\n"
                    
                    ['Create', 'Update', 'Replace', 'Delete'].each { action ->
                        pr_comment += "**${action}**\n"

                        if (tf_changes[action].size() == 0) {
                            pr_comment += "None\n"
                        } else {
                            pr_comment += "| Module | Type | Name |\n| --- | --- | --- |\n"

                            tf_changes[action].each { resource ->
                                def module = resource.module_address == null ? '' : resource.module_address.replace('module.', '')
                                def type = resource.type
                                def name = resource.name

                                if (resource.index != null) {
                                    name += "[${resource.index}]"
                                }

                                pr_comment += "| ${module} | ${type} | ${name} |\n"
                            }
                        }

                        pr_comment += "\n"
                    }

                    pr_comment += "Please review the changes, gain any necessary approvals and comment with **/ok** to deploy the changes."
                    pullRequest.comment(pr_comment)
                }
            }
        }

        stage('Terraform: Apply') {
            when {
                allOf {
                    equals expected: 'COMMENT_OK', actual: TRIGGER
                    equals expected: 'false', actual: DIRTY_PLAN
                    anyOf {
                        changeRequest target: 'main'
                    }
                }
            }

            steps {
                script {

                    // Exit this stage if the PR is not mergeable
                    if (! pullRequest.mergeable) {
                        pullRequest.comment("**This PR is not in a mergeable state. Please address the merge issues and try again.**")
                        return
                    }
                    
                    // Get the PR merge status - https://developer.github.com/v4/enum/mergestatestatus/
                    def github_url_components = env.GIT_URL.replace('https://github.com/', '').replace('git@github.com:', '').replace('.git', '').split('/')
                    def github_api_response = httpRequest (
                        url: "https://api.github.com/graphql",
                        customHeaders: [
                            [
                                "name": "Authorization",
                                "value": "Bearer ${env.GIT_TOKEN}"
                            ],
                            [
                                "name": "Accept",
                                "value": "application/vnd.github.merge-info-preview+json"
                            ]
                        ],
                        httpMode: "POST",
                        requestBody: "{\"query\": \"query { repository(owner: \\\"${github_url_components[0]}\\\", name: \\\"${github_url_components[1]}\\\") { pullRequest(number: ${env.CHANGE_ID}) { mergeStateStatus } } }\"}"
                    )
                    def github_api_response_body = readJSON text: github_api_response.content
                    def merge_status = github_api_response_body.data.repository.pullRequest.mergeStateStatus

                    // Exit this stage if PR merge is blocked
                    if (merge_status == 'BLOCKED') {
                        pullRequest.comment("**Merging of this PR is blocked. Please ensure that all necessary approvals have been given.**")
                        return
                    }

                    // Apply the changes
                    sh "terraform/terraform apply plan.out"

                    // Merge the PR
                    def mergeMethod = config.buildBranchOverride != null || env.CHANGE_TARGET == 'dev' ? 'squash' : 'merge'

                    pullRequest.merge(commitTitle: "${pullRequest.title} (#${env.CHANGE_ID})", commitMessage: pullRequest.body, mergeMethod: mergeMethod)

                    // Delete the hash from S3
                    sh "aws s3 rm s3://${env.TF_STATE_BUCKET}/${env.CHANGE_ID}.hash"

                    // Delete the feature branch
                    if (! ['dev', 'nonprod', 'preprod', 'master'].contains(env.CHANGE_BRANCH)) {
                        sh "git push -d origin ${env.CHANGE_BRANCH}"
                    }
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
    }
}
