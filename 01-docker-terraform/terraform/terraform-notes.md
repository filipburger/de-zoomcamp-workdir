Good question. The full workflow and why each step exists:

**`terraform fmt`** — formats your `.tf` files to canonical style. Purely cosmetic, like `black` for Python. Run it before committing so your code looks consistent. Not strictly necessary but good habit.

**`terraform init`** — downloads the provider plugins (in your case the Google provider `4.51.0`). Must run once when you first set up or when you change providers. Creates the `.terraform/` folder. Think of it like `uv sync` — sets up dependencies before you can do anything.

**`terraform plan`** — shows exactly what Terraform *would* do without touching anything. The value over just using apply is:

- In CI/CD pipelines you run plan automatically on every PR so a human can review infrastructure changes before they're applied — same as code review
- On large production setups with 50+ resources you want to verify only the expected 2 resources are being modified, not 48
- Catch mistakes before they cost money or cause outages

For a course with 2 resources it feels redundant since `apply` shows you the plan anyway and asks for confirmation. In real infrastructure work it's essential.

**`terraform apply`** — executes the plan, creates/modifies real resources. Shows the plan first, requires `yes` confirmation.

**`terraform destroy`** — tears everything down. Your most important command for cost control — run this at the end of every session.

**What's missing from what you listed:**

```hcl
terraform validate    # checks syntax before plan, faster than plan
terraform state list  # shows what terraform is currently tracking
terraform output      # shows output values you've defined
```

`validate` is worth adding to your habit — faster than `plan` for catching typos in config files.

For the course the essential flow is really just `init` once, then `apply` to create and `destroy` to clean up.

