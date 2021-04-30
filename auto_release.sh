#!/bin/bash -l

semanticVersionToAbstractValue() {
  VER=$1
  MAJOR=$(echo $VER | awk 'match($0, /^([0-9]+)\.([0-9]+)\.([0-9]+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+)?$/, groups) { print groups[1] }')
  MINOR=$(echo $VER | awk 'match($0, /^([0-9]+)\.([0-9]+)\.([0-9]+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+)?$/, groups) { print groups[2] }')
  PATCH=$(echo $VER | awk 'match($0, /^([0-9]+)\.([0-9]+)\.([0-9]+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+)?$/, groups) { print groups[3] }')

  echo $(($MAJOR * 100 + $MINOR * 10 + $PATCH))
}

TARGET_FILE="./build.gradle"
if [ ! -e $TARGET_FILE ]; then
  TARGET_FILE="./build.gradle.kts"
  if [ ! -e $TARGET_FILE ]; then
    echo "Gradle configuration file not found!"
    exit
  fi
fi


REPOSITORY_NAME=$(echo "$GITHUB_REPOSITORY" | awk -F / '{print $2}')

PROJECT_VERSION=$(cat $TARGET_FILE | grep -m 1 "version = " | awk 'match($0, /version = "(.+)"/, groups) { print groups[1] }')
REMOTE_LATEST_VERSION=$(curl --silent "https://api.github.com/repos/$GITHUB_REPOSITORY/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

ABSTRACT_PROJECT_VERSION=$(semanticVersionToAbstractValue $PROJECT_VERSION)
ABSTRACT_REMOTE_VERSION=$(semanticVersionToAbstractValue $REMOTE_LATEST_VERSION)

echo "Repository: $REPOSITORY_NAME"
echo "Project Version: $PROJECT_VERSION :$ABSTRACT_PROJECT_VERSION"
echo "Release Version: $REMOTE_LATEST_VERSION :$ABSTRACT_REMOTE_VERSION"

if [ $ABSTRACT_PROJECT_VERSION -gt $ABSTRACT_REMOTE_VERSION ]; then

  sh ./gradlew shadow

  RELEASE_ID=$(curl --request POST \
    --url "https://api.github.com/repos/$GITHUB_REPOSITORY/releases" \
    --header "authorization: Bearer $GITHUB_TOKEN" \
    --header "accept: application/vnd.github.v3+json" \
    --header "content-type: application/json" \
    --data "{
    \"name\": \"$REPOSITORY_NAME\",
    \"tag_name\": \"$PROJECT_VERSION\",
    \"draft\": false,
    \"prerelease\": false
  }" | grep '"id":' | sed -E 's/.*"([^"]+)".*/\1/')

  echo "Release ID: $RELEASE_ID https://api.github.com/repos/$GITHUB_REPOSITORY/releases/$RELEASE_ID/assets"

  curl --request POST \
    --url "https://api.github.com/repos/$GITHUB_REPOSITORY/releases/$RELEASE_ID/assets?name=$REPOSITORY_NAME-mod-v$PROJECT_VERSION&label=$REPOSITORY_NAME-mod-v$PROJECT_VERSION" \
    --header "authorization: Bearer $GITHUB_TOKEN" \
    --header "accept: application/vnd.github.v3+json" \
    --header "content-type: application/java-archiver" \
    --data-binary @"./output/mod.jar"

  curl --request POST \
    --url "https://api.github.com/repos/$GITHUB_REPOSITORY/releases/$RELEASE_ID/assets?name=$REPOSITORY_NAME-plugin-v$PROJECT_VERSION&label=$REPOSITORY_NAME-plugin-v$PROJECT_VERSION" \
    --header "authorization: Bearer $GITHUB_TOKEN" \
    --header "accept: application/vnd.github.v3+json" \
    --header "content-type: application/java-archiver" \
    --data-binary @"./output/plugin.jar"
fi