load("render.star", "render")

def main():
    return render.Root(
        child = render.Box(
            child = render.Column(
                expanded=True,
                main_align="center",
                cross_align="center",
                children = [
                    render.Text(content="LIVE FEEDS", color="#00ff00", font="6x10"),
                    render.Text(content="READY!", color="#ffffff"),
                ],
            ),
        )
    )
