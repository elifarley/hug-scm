# Installation

Getting started with Hug SCM is straightforward.

It's designed to be installed directly from its Github repository, and doesn't require root privileges.

## Prerequisites

- **Git or Mercurial**: Hug requires an underlying SCM tool. It works with both Git and Mercurial (Hg), so you must have at least one installed and available in your `PATH`.
- **Bash shell**: Hug is a Bash-based tool and requires Bash 4.0 or higher. 

## Installation Steps

1.  **Clone the Repository**

    First, clone the **Hug SCM** repository to a permanent location on your local machine. A common choice is your home directory.

    ```shell
    cd $HOME # or any other directory
    git clone https://github.com/elifarley/hug-scm.git
    ```

2.  **Run the Installer**

    ```shell
    $HOME/hug-scm/install.sh
    ```

`hug` will be available for any future terminal sessions you open.

3.  **Activate Hug**

    For the `hug` command to be immediately available in your current terminal session, you need to activate it.
    Just follow the installer instructions to do so.

    Alternatively, you can simply open a new terminal window.

4.  **Verify the Installation**

    You're all set! To confirm that Hug is installed correctly, run the status command.

    ```shell
    hug s
    ```

    You can also see a list of all available command families by running:

    ```shell
    hug help
    ```

You are now ready to use Hug SCM in any of your Git repositories.

## Mercurial Support

Hug also supports Mercurial repositories! After installing Hug for Git (steps above), you can optionally install Mercurial support:

```shell
cd $HOME/hug-scm/hg-config
./install.sh
```

Once installed, Hug will automatically detect whether you're in a Git or Mercurial repository and use the appropriate commands. The same familiar Hug commands work in both!

See [Mercurial Support](../README.md#mercurial-support) in the main README for more details on Mercurial-specific features and limitations.
