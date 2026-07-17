import { LANDING_CONTENT } from "./landing-content";
import { ScrollFloatText } from "./ScrollFloatText";

export function CommunityCta() {
  const community = LANDING_CONTENT.community;

  return (
    <section
      aria-labelledby="community-title"
      className="community-cta"
      data-ring-chapter="community"
    >
      <div className="community-copy">
        <p>我们正在寻找第一批体验者</p>
        <ScrollFloatText id="community-title" text={community.title} />
        <p>{community.description}</p>
      </div>

      <div className="community-qr-frame">
        <img
          alt="内测群二维码待替换"
          data-testid="community-qr"
          src="/community/eureka-ring-beta-qr-placeholder.svg"
        />
      </div>
    </section>
  );
}
